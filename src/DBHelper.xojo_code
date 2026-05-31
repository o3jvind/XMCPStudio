#tag Module
Protected Module DBHelper

	#tag Property, Flags = &h0
		DB As SQLiteDatabase
	#tag EndProperty

	#tag Method, Flags = &h0
		Sub InitDB(f As FolderItem)
		  ' Raises DatabaseException on failure (locked file, corrupt DB, missing
		  ' parent folder). Caller is responsible for surfacing the error.
		  DB = New SQLiteDatabase
		  DB.DatabaseFile = f
		  DB.Connect
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSetting(key As String, defaultValue As String) As String
		  If DB = Nil Then Return defaultValue
		  Try
		    Var rs As RowSet = DB.SelectSQL("SELECT value FROM app_settings WHERE key=?", key)
		    If rs.AfterLastRow Then
		      rs.Close
		      Return defaultValue
		    End If
		    Var v As String = rs.Column("value").StringValue
		    rs.Close
		    Return v
		  Catch e As DatabaseException
		    System.DebugLog("DBHelper.GetSetting failed: " + e.Message)
		    Return defaultValue
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetSetting(key As String, value As String)
		  If DB = Nil Then Return
		  Try
		    DB.ExecuteSQL("INSERT INTO app_settings (key, value) VALUES (?, ?) " _
		      + "ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
		  Catch e As DatabaseException
		    System.DebugLog("DBHelper.SetSetting failed: " + e.Message)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function CreateJob(name As String, prompt As String, description As String, tags As String) As Boolean
		  ' Returns True on success, False on failure (and reports a dialog).
		  ' Callers must gate UI updates (close window, clear dirty flag, refresh list)
		  ' on the return value so a failed write isn't presented as success.
		  If DB = Nil Then Return False
		  Try
		    Var rs As RowSet = DB.SelectSQL("SELECT MAX(sort) AS ms FROM jobs")
		    Var maxSort As Integer = 0
		    If Not rs.AfterLastRow Then maxSort = rs.Column("ms").IntegerValue
		    rs.Close
		    DB.ExecuteSQL("INSERT INTO jobs (name, prompt, description, tags, sort) VALUES (?,?,?,?,?)", _
		      name, prompt, description, tags, maxSort + 1)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("CreateJob", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function UpdateJob(id As Integer, name As String, prompt As String, description As String, tags As String) As Boolean
		  If DB = Nil Then Return False
		  Try
		    DB.ExecuteSQL("UPDATE jobs SET name=?, prompt=?, description=?, tags=? WHERE id=?", _
		      name, prompt, description, tags, id)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("UpdateJob", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetJobById(id As Integer) As Dictionary
		  Var d As New Dictionary
		  If DB = Nil Then Return d
		  Try
		    Var rs As RowSet = DB.SelectSQL("SELECT id, name, prompt, description, tags FROM jobs WHERE id=?", id)
		    If rs.AfterLastRow Then
		      rs.Close
		      Return d
		    End If
		    d.Value("id")          = rs.Column("id").IntegerValue
		    d.Value("name")        = rs.Column("name").StringValue
		    d.Value("prompt")      = rs.Column("prompt").StringValue
		    d.Value("description") = rs.Column("description").StringValue
		    d.Value("tags")        = rs.Column("tags").StringValue
		    rs.Close
		  Catch e As DatabaseException
		    ReportDBError("GetJobById", e)
		  End Try
		  Return d
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function DeleteJob(id As Integer) As Boolean
		  If DB = Nil Then Return False
		  Try
		    DB.ExecuteSQL("DELETE FROM jobs WHERE id=?", id)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("DeleteJob", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReorderJob(fromId As Integer, toId As Integer) As Boolean
		  If DB = Nil Then Return False
		  Try
		    Var rsF As RowSet = DB.SelectSQL("SELECT sort FROM jobs WHERE id=?", fromId)
		    Var rsT As RowSet = DB.SelectSQL("SELECT sort FROM jobs WHERE id=?", toId)
		    If rsF.AfterLastRow Or rsT.AfterLastRow Then
		      rsF.Close
		      rsT.Close
		      Return False
		    End If
		    Var sortF As Integer = rsF.Column("sort").IntegerValue
		    Var sortT As Integer = rsT.Column("sort").IntegerValue
		    rsF.Close
		    rsT.Close
		    DB.ExecuteSQL("UPDATE jobs SET sort=? WHERE id=?", sortT, fromId)
		    DB.ExecuteSQL("UPDATE jobs SET sort=? WHERE id=?", sortF, toId)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("ReorderJob", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetJobsJSON() As String
		  If DB = Nil Then Return "[]"
		  Try
		    Var rs As RowSet = DB.SelectSQL("SELECT id, name, prompt, description, tags FROM jobs ORDER BY sort, id")
		    Var result As String = "["
		    Var first As Boolean = True
		    While Not rs.AfterLastRow
		      If Not first Then result = result + ","
		      first = False
		      result = result + "{" _
		        + """id"":" + rs.Column("id").IntegerValue.ToString + "," _
		        + """name"":" + JSONEscape(rs.Column("name").StringValue) + "," _
		        + """prompt"":" + JSONEscape(rs.Column("prompt").StringValue) + "," _
		        + """description"":" + JSONEscape(rs.Column("description").StringValue) + "," _
		        + """tags"":" + JSONEscape(rs.Column("tags").StringValue) _
		        + "}"
		      rs.MoveToNextRow
		    Wend
		    rs.Close
		    Return result + "]"
		  Catch e As DatabaseException
		    ReportDBError("GetJobsJSON", e)
		    Return "[]"
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function UniqueNoteTitle(title As String, excludeId As Integer, scope As String, projectPath As String) As String
		  ' Collisions only matter within the same scope+project bucket. A "TODO"
		  ' in project A and a "TODO" in project B are fine; same for "TODO" global
		  ' vs "TODO" project.
		  Var candidate As String = title
		  Var n As Integer = 2
		  While True
		    Var rs As RowSet = DB.SelectSQL( _
		      "SELECT COUNT(*) AS cnt FROM notes WHERE title=? AND id<>? AND scope=? AND project_path=?", _
		      candidate, excludeId, scope, projectPath)
		    Var cnt As Integer = rs.Column("cnt").IntegerValue
		    rs.Close
		    If cnt = 0 Then Return candidate
		    candidate = title + " " + n.ToString
		    n = n + 1
		  Wend
		  Return candidate
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function CreateNote(title As String, body As String, tags As String, description As String, scope As String, projectPath As String) As Boolean
		  If DB = Nil Then Return False
		  Try
		    Var safeScope As String = If(scope = "project", "project", "global")
		    Var safePath As String = If(safeScope = "project", projectPath, "")
		    Var safeTitle As String = UniqueNoteTitle(title, 0, safeScope, safePath)
		    Var rs As RowSet = DB.SelectSQL("SELECT MAX(sort) AS ms FROM notes")
		    Var maxSort As Integer = 0
		    If Not rs.AfterLastRow Then maxSort = rs.Column("ms").IntegerValue
		    rs.Close
		    DB.ExecuteSQL("INSERT INTO notes (title, body, tags, description, scope, project_path, sort) VALUES (?,?,?,?,?,?,?)", _
		      safeTitle, body, tags, description, safeScope, safePath, maxSort + 1)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("CreateNote", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function UpdateNote(id As Integer, title As String, body As String, tags As String, description As String, scope As String, projectPath As String) As Boolean
		  If DB = Nil Then Return False
		  Try
		    Var safeScope As String
		    If scope = "project" Then
		      safeScope = "project"
		    ElseIf scope = "orphaned" Then
		      safeScope = "orphaned"
		    Else
		      safeScope = "global"
		    End If
		    Var safePath As String = If(safeScope = "project" Or safeScope = "orphaned", projectPath, "")
		    Var safeTitle As String = UniqueNoteTitle(title, id, safeScope, safePath)
		    DB.ExecuteSQL( _
		      "UPDATE notes SET title=?, body=?, tags=?, description=?, scope=?, project_path=?, updated=datetime('now') WHERE id=?", _
		      safeTitle, body, tags, description, safeScope, safePath, id)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("UpdateNote", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function DeleteNote(id As Integer) As Boolean
		  If DB = Nil Then Return False
		  Try
		    DB.ExecuteSQL("DELETE FROM notes WHERE id=?", id)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("DeleteNote", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReorderNote(fromId As Integer, toId As Integer) As Boolean
		  If DB = Nil Then Return False
		  Try
		    Var rsF As RowSet = DB.SelectSQL("SELECT sort FROM notes WHERE id=?", fromId)
		    Var rsT As RowSet = DB.SelectSQL("SELECT sort FROM notes WHERE id=?", toId)
		    If rsF.AfterLastRow Or rsT.AfterLastRow Then
		      rsF.Close
		      rsT.Close
		      Return False
		    End If
		    Var sortF As Integer = rsF.Column("sort").IntegerValue
		    Var sortT As Integer = rsT.Column("sort").IntegerValue
		    rsF.Close
		    rsT.Close
		    DB.ExecuteSQL("UPDATE notes SET sort=? WHERE id=?", sortT, fromId)
		    DB.ExecuteSQL("UPDATE notes SET sort=? WHERE id=?", sortF, toId)
		    Return True
		  Catch e As DatabaseException
		    ReportDBError("ReorderNote", e)
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetNotesJSON(projectPath As String) As String
		  If DB = Nil Then Return "[]"
		  Try
		    Var rs As RowSet = DB.SelectSQL( _
		      "SELECT id, title, body, tags, description, scope, project_path FROM notes " _
		      + "WHERE scope='global' OR scope='orphaned' OR (scope='project' AND project_path=?) " _
		      + "ORDER BY scope, sort, id", projectPath)
		    Var result As String = "["
		    Var first As Boolean = True
		    While Not rs.AfterLastRow
		      Var noteScope As String = rs.Column("scope").StringValue
		      Var notePath As String = rs.Column("project_path").StringValue
		      // Project notes whose folder no longer exists are shown as orphaned
		      If noteScope = "project" And notePath <> "" And notePath <> projectPath Then
		        Var f As New FolderItem(notePath, FolderItem.PathModes.Native)
		        If f = Nil Or Not f.Exists Then noteScope = "orphaned"
		      End If
		      If Not first Then result = result + ","
		      first = False
		      result = result + "{" _
		        + """id"":" + rs.Column("id").IntegerValue.ToString + "," _
		        + """scope"":" + JSONEscape(noteScope) + "," _
		        + """title"":" + JSONEscape(rs.Column("title").StringValue) + "," _
		        + """body"":" + JSONEscape(rs.Column("body").StringValue) + "," _
		        + """tags"":" + JSONEscape(rs.Column("tags").StringValue) + "," _
		        + """description"":" + JSONEscape(rs.Column("description").StringValue) _
		        + "}"
		      rs.MoveToNextRow
		    Wend
		    rs.Close
		    Return result + "]"
		  Catch e As DatabaseException
		    ReportDBError("GetNotesJSON", e)
		    Return "[]"
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function HasProjectNotes(projectPath As String) As Boolean
		  If DB = Nil Then Return False
		  Try
		    Var rs As RowSet = DB.SelectSQL( _
		      "SELECT COUNT(*) AS cnt FROM notes WHERE scope='project' AND project_path=?", projectPath)
		    Var cnt As Integer = 0
		    If Not rs.AfterLastRow Then cnt = rs.Column("cnt").IntegerValue
		    rs.Close
		    Return cnt > 0
		  Catch e As DatabaseException
		    ReportDBError("HasProjectNotes", e)
		    Return True  ' fail-closed: don't reseed if we can't read
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SeedNotesForProject(projectPath As String, titles() As String)
		  If DB = Nil Then Return
		  If projectPath = "" Then Return
		  If HasProjectNotes(projectPath) Then Return

		  Try
		    Var rs As RowSet = DB.SelectSQL("SELECT MAX(sort) AS ms FROM notes")
		    Var maxSort As Integer = 0
		    If Not rs.AfterLastRow Then maxSort = rs.Column("ms").IntegerValue
		    rs.Close

		    For Each t As String In titles
		      If t = "" Then Continue
		      maxSort = maxSort + 1
		      DB.ExecuteSQL("INSERT INTO notes (title, body, scope, project_path, sort) VALUES (?,?,?,?,?)", _
		        t, "", "project", projectPath, maxSort)
		    Next
		  Catch e As DatabaseException
		    ReportDBError("SeedNotesForProject", e)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function HasAnyJobs() As Boolean
		  If DB = Nil Then Return False
		  Try
		    Var rs As RowSet = DB.SelectSQL("SELECT COUNT(*) AS cnt FROM jobs")
		    Var cnt As Integer = 0
		    If Not rs.AfterLastRow Then cnt = rs.Column("cnt").IntegerValue
		    rs.Close
		    Return cnt > 0
		  Catch e As DatabaseException
		    ReportDBError("HasAnyJobs", e)
		    Return True  ' fail-closed: don't reseed if we can't read
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SeedStarterJobs(names() As String, prompts() As String, descriptions() As String, tags() As String)
		  ' Parallel-array seed so callers don't need a Pair-of-strings construct.
		  If DB = Nil Then Return
		  If names.LastRowIndex <> prompts.LastRowIndex Then Return
		  If names.LastRowIndex <> descriptions.LastRowIndex Then Return
		  If names.LastRowIndex <> tags.LastRowIndex Then Return
		  If HasAnyJobs() Then Return

		  Try
		    For i As Integer = 0 To names.LastRowIndex
		      DB.ExecuteSQL("INSERT INTO jobs (name, prompt, description, tags, sort) VALUES (?,?,?,?,?)", _
		        names(i), prompts(i), descriptions(i), tags(i), i + 1)
		    Next
		  Catch e As DatabaseException
		    ReportDBError("SeedStarterJobs", e)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SeedProject(projectPath As String)
		  If projectPath <> "" Then
		    Var titles() As String
		    titles.Add("Architecture")
		    titles.Add("TODO")
		    titles.Add("Decisions")
		    titles.Add("Glossary")
		    SeedNotesForProject(projectPath, titles)
		  End If

		  Var names() As String
		  Var prompts() As String
		  Var descriptions() As String
		  Var tags() As String

		  names.Add("Explain current file")
		  prompts.Add("Use the get_code MCP tool to read the currently selected item in the Xojo IDE, then summarize what it does in plain language and call out anything non-obvious.")
		  descriptions.Add("Summarize the file currently open in the IDE")
		  tags.Add("explain,read,summary,understand,onboarding")

		  names.Add("Add unit tests for selection")
		  prompts.Add("Read the currently selected method or class in the Xojo IDE and propose unit tests that cover its main behaviours and edge cases. Output the test code, don't modify the project yet.")
		  descriptions.Add("Propose tests for the selected method/class")
		  tags.Add("tests,unit-tests,coverage,quality,tdd")

		  names.Add("Refactor for readability")
		  prompts.Add("Read the currently selected code in the Xojo IDE and propose a refactor that improves readability without changing behaviour. Show the diff first and wait for approval before applying.")
		  descriptions.Add("Improve readability without changing behavior")
		  tags.Add("refactor,cleanup,readability,quality,rewrite")

		  names.Add("Find dead code in this project")
		  prompts.Add("Survey this Xojo project's source via the XMCP MCP tools and list methods, properties, and constants that appear to be unreferenced. Don't delete anything — just report findings.")
		  descriptions.Add("List unreferenced methods, properties, constants")
		  tags.Add("audit,dead-code,unused,cleanup,housekeeping")

		  names.Add("Review recent commits")
		  prompts.Add("Run `git log -n 20 --oneline` and then `git show` on the last few commits. Summarize what's changed lately and flag anything that looks risky or incomplete.")
		  descriptions.Add("Summarize recent git activity and flag risk")
		  tags.Add("git,review,history,changes,log,commits")

		  names.Add("Generate ARCHITECTURE.md outline")
		  prompts.Add("Survey the project structure via XMCP and the filesystem, then propose an outline for an ARCHITECTURE.md that documents the main modules, their responsibilities, and how they connect.")
		  descriptions.Add("Propose an outline for ARCHITECTURE.md")
		  tags.Add("docs,architecture,documentation,overview,markdown")

		  names.Add("Check for unhandled errors")
		  prompts.Add("Search this Xojo project for Try blocks and Raise statements. Report any catches that swallow exceptions silently or any code paths where errors aren't surfaced to the user or the debug log.")
		  descriptions.Add("Find silent catches and unsurfaced exceptions")
		  tags.Add("audit,errors,exceptions,try-catch,robustness,reliability")

		  names.Add("Suggest performance improvements")
		  prompts.Add("Read the currently selected code and identify likely hot paths or wasteful patterns (repeated lookups, redundant allocations, N+1 queries, etc.). Propose specific changes.")
		  descriptions.Add("Find slow patterns in the current selection")
		  tags.Add("perf,performance,optimize,speed,hotpath")

		  names.Add("Build the project and fix errors")
		  prompts.Add("Use the build_project MCP tool. If it succeeds, report success. If it fails, parse the errors, identify root causes, propose fixes, and (with approval) apply them.")
		  descriptions.Add("Build, then diagnose and fix any failures")
		  tags.Add("build,compile,errors,fix,xmcp,mcp")

		  names.Add("Summarize the debug log")
		  prompts.Add("Use the get_debug_log MCP tool to fetch the most recent debug log. Summarize what happened in the most recent run and flag any exceptions or warnings.")
		  descriptions.Add("Surface exceptions and warnings from the last run")
		  tags.Add("debug,log,exceptions,runtime,diagnostics,xmcp")

		  SeedStarterJobs(names, prompts, descriptions, tags)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ReportDBError(op As String, e As RuntimeException)
		  ' Centralised user-visible error path for CRUD operations after startup.
		  ' Locked file, corrupt page, disk full, etc. all surface here. We log a
		  ' detailed line for support and show the user a plain dialog so the
		  ' action isn't silently lost.
		  System.DebugLog("DBHelper." + op + " failed: " + e.Message)
		  Var dlg As New MessageDialog
		  dlg.Message = "Database error"
		  dlg.Explanation = "The " + op + " operation could not complete." _
		    + Chr(10) + Chr(10) + e.Message _
		    + Chr(10) + Chr(10) _
		    + "If this keeps happening, quit XMCPStudio and check that the database file isn't locked by another process."
		  dlg.ActionButton.Caption = "OK"
		  Call dlg.ShowModalWithin(Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function JSONEscape(s As String) As String
		  s = s.ReplaceAll("\", "\\")
		  s = s.ReplaceAll("""", "\""")
		  s = s.ReplaceAll(Chr(13), "\r")
		  s = s.ReplaceAll(Chr(10), "\n")
		  s = s.ReplaceAll(Chr(9),  "\t")
		  Return """" + s + """"
		End Function
	#tag EndMethod


	#tag Method, Flags = &h0
		Function AsJSONItem(v As Variant) As JSONItem
		  If v.IsNull Then Return Nil
		  If v IsA JSONItem Then Return JSONItem(v)
		  Return Nil
		End Function
	#tag EndMethod

End Module
#tag EndModule
