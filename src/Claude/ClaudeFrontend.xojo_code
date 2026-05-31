#tag Class
Protected Class ClaudeFrontend
Inherits AIFrontend
	#tag Method, Flags = &h0
		Function ModelList() As String
		  If mCachedModelList <> "" Then Return mCachedModelList
		  Return StaticModelList()
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub FetchModelListAsync(viewer As ChatView)
		  Var apiKey As String = Secrets.Get("Anthropic", "APIKey")
		  If apiKey = "" Then Return
		  mPendingDelegate = viewer
		  mModelConn = New URLConnection
		  mModelConn.RequestHeader("x-api-key") = apiKey
		  mModelConn.RequestHeader("anthropic-version") = "2023-06-01"
		  AddHandler mModelConn.ContentReceived, WeakAddressOf ModelListContentReceived
		  mModelConn.Send("GET", "https://api.anthropic.com/v1/models")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ModelListContentReceived(sender As URLConnection, url As String, httpStatus As Integer, content As String)
		  #Pragma Unused sender
		  #Pragma Unused url
		  mModelConn = Nil
		  Var viewer As ChatView = mPendingDelegate
		  mPendingDelegate = Nil
		  If httpStatus <> 200 Then Return
		  Var root As JSONItem
		  Try
		    root = New JSONItem(content)
		  Catch e As JSONException
		    Return
		  End Try
		  Var data As JSONItem
		  Try
		    data = root.Value("data")
		  Catch e As RuntimeException
		    Return
		  End Try
		  If data = Nil Or Not data.IsArray Or data.Count = 0 Then Return
		  Var result As String = "["
		  Var first As Boolean = True
		  For i As Integer = 0 To data.Count - 1
		    Var m As JSONItem
		    Try
		      m = data.ValueAt(i)
		    Catch e As RuntimeException
		      Continue
		    End Try
		    If m = Nil Then Continue
		    Var mid As String = m.Lookup("id", "")
		    Var label As String = m.Lookup("display_name", mid)
		    If mid = "" Then Continue
		    If Not first Then result = result + ","
		    first = False
		    result = result + "{""value"":" + DBHelper.JSONEscape(mid) + ",""label"":" + DBHelper.JSONEscape(label) + "}"
		  Next
		  If first Then Return
		  result = result + "]"
		  If result = mCachedModelList Then Return
		  mCachedModelList = result
		  If viewer <> Nil Then
		    viewer.LoadBackendUI(App.BuildBackendUIConfig())
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StaticModelList() As String
		  Return "[" _
		  + "{""value"":""__api_key_hint"",""label"":""Add API key for live list"",""disabled"":true}," _
		  + "{""value"":""claude-opus-4-8"",""label"":""Claude Opus 4.8""}," _
		  + "{""value"":""claude-opus-4-7"",""label"":""Claude Opus 4.7""}," _
		  + "{""value"":""claude-sonnet-4-6"",""label"":""Claude Sonnet 4.6""}," _
		  + "{""value"":""claude-haiku-4-5-20251001"",""label"":""Claude Haiku 4.5""}" _
		  + "]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ModeOptions() As String
		  Return "[" _
		  + "{""value"":""ask"",""label"":""Ask before edits""}," _
		  + "{""value"":""auto"",""label"":""Edit automatically""}," _
		  + "{""value"":""plan"",""label"":""Plan mode""}" _
		  + "]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SessionList(projectPath As String) As String
		  If projectPath = "" Then Return "[]"
		  Var claudeProjects As FolderItem = SpecialFolder.UserHome.Child(".claude").Child("projects")
		  If claudeProjects = Nil Or Not claudeProjects.Exists Then Return "[]"
		  
		  Var slugCandidates() As String
		  slugCandidates.Add(projectPath.ReplaceAll("/", "-"))
		  Var projectFolder As FolderItem = New FolderItem(projectPath, FolderItem.PathModes.Native)
		  Var parentPath As String = If(projectFolder.Parent <> Nil, projectFolder.Parent.NativePath, "")
		  If parentPath <> "" And parentPath <> projectPath Then
		    slugCandidates.Add(parentPath.ReplaceAll("/", "-"))
		  End If
		  
		  Var files() As FolderItem
		  Var modTimes() As Double
		  Var seenUUIDs As New Dictionary
		  For Each slug As String In slugCandidates
		    Var dir As FolderItem = claudeProjects.Child(slug)
		    If dir = Nil Or Not dir.Exists Then Continue
		    Var count As Integer = dir.Count
		    Var i As Integer
		    For i = 1 To count
		      Var f As FolderItem = dir.ChildAt(i - 1)
		      If f = Nil Or f.IsFolder Then Continue
		      If Not f.Name.EndsWith(".jsonl") Then Continue
		      Var uuid As String = f.Name.Left(f.Name.Length - 6)
		      If seenUUIDs.HasKey(uuid) Then Continue
		      seenUUIDs.Value(uuid) = True
		      files.Add(f)
		      modTimes.Add(f.ModificationDate.TotalSeconds)
		    Next
		  Next
		  
		  Var i As Integer
		  Var n As Integer = files.LastRowIndex
		  For i = 0 To n - 1
		    Var maxIdx As Integer = i
		    For j As Integer = i + 1 To n
		      If modTimes(j) > modTimes(maxIdx) Then maxIdx = j
		    Next
		    If maxIdx <> i Then
		      Var tf As FolderItem = files(i)
		      files(i) = files(maxIdx)
		      files(maxIdx) = tf
		      Var tm As Double = modTimes(i)
		      modTimes(i) = modTimes(maxIdx)
		      modTimes(maxIdx) = tm
		    End If
		  Next
		  
		  Var limit As Integer = If(n + 1 < 50, n + 1, 50)
		  Var result As String = "["
		  Var first As Boolean = True
		  For i = 0 To limit - 1
		    Var f As FolderItem = files(i)
		    If f = Nil Then Continue
		    Var uuid As String = f.Name
		    If uuid.Right(6) = ".jsonl" Then uuid = uuid.Left(uuid.Length - 6)
		    
		    Var previewLines() As String
    Try
      Var ts As TextInputStream = TextInputStream.Open(f)
      ts.Encoding = Encodings.UTF8
      Var lineCount As Integer = 0
      While Not ts.EndOfFile And lineCount < 20
        previewLines.Add(ts.ReadLine)
        lineCount = lineCount + 1
      Wend
      ts.Close
    Catch ioe As IOException
      System.DebugLog("ClaudeFrontend.SessionList: skipping " + f.Name + " — " + ioe.Message)
      Continue
    End Try

    Var title As String = ""
    For Each pLine As String In previewLines
		      pLine = pLine.Trim
		      If pLine = "" Then Continue
		      Var pItem As JSONItem
		      Try
		        pItem = New JSONItem(pLine)
		      Catch e As JSONException
		      End Try
		      If pItem = Nil Then Continue
		      Var pType As String = pItem.Lookup("type", "")
		      If pType = "ai-title" Then
		        title = pItem.Lookup("aiTitle", "")
		        Exit
		      End If
		      If title = "" And pType = "user" Then
		        Var msg As JSONItem = AsJSONItem(pItem.Lookup("message", ""))
		        If msg <> Nil Then
		          Var contentVar As Variant = msg.Lookup("content", "")
		          Var contentStr As String
		          If contentVar.Type = Variant.TypeString Then
		            contentStr = contentVar
		          Else
		            Var contentArr As JSONItem = AsJSONItem(contentVar)
		            If contentArr <> Nil And contentArr.IsArray Then
		              Var ci As Integer
		              For ci = 0 To contentArr.Count - 1
		                Var block As JSONItem = AsJSONItem(contentArr.ValueAt(ci))
		                If block <> Nil And block.Lookup("type", "") = "text" Then
		                  contentStr = block.Lookup("text", "")
		                  Exit
		                End If
		              Next
		            End If
		          End If
		          contentStr = contentStr.Trim
		          If contentStr.Length > 10 And contentStr.Left(1) <> "<" Then
		            If contentStr.Length > 60 Then contentStr = contentStr.Left(60) + "…"
		            title = contentStr
		          End If
		        End If
		      End If
		      If title <> "" Then Exit
		    Next
		    If title = "" Then title = uuid.Left(8) + "…"
		    If title = "Warmup" Then Continue
		    
		    Var md As Date = f.ModificationDate
		    Var dateStr As String = FormatDate(md)
		    
		    If Not first Then result = result + ","
		    first = False
		    result = result + "{" _
		    + """uuid"":" + DBHelper.JSONEscape(uuid) + "," _
		    + """title"":" + DBHelper.JSONEscape(title) + "," _
		    + """date"":" + DBHelper.JSONEscape(dateStr) _
		    + "}"
		  Next
		  Return result + "]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function SkillDescription(f As FolderItem) As String
		  Var preview As String = ""
		  Try
		    Var ts As TextInputStream = TextInputStream.Open(f)
		    ts.Encoding = Encodings.UTF8
		    preview = ts.Read(1024)
		    ts.Close
		  Catch e As IOException
		    System.DebugLog("ClaudeFrontend.SkillDescription: " + f.Name + " — " + e.Message)
		    Return ""
		  End Try

		  Var inFrontmatter As Boolean = False
		  Var frontmatterDone As Boolean = False
		  Var lineCount As Integer = 0
		  For Each line As String In preview.Split(Chr(10))
		    line = line.Trim
		    lineCount = lineCount + 1
		    If lineCount = 1 And line = "---" Then
		      inFrontmatter = True
		      Continue
		    End If
		    If inFrontmatter Then
		      If line = "---" Then
		        inFrontmatter = False
		        frontmatterDone = True
		      ElseIf line.Left(12) = "description:" Then
		        Var desc As String = line.Mid(13).Trim
		        If desc <> "" Then Return desc
		      End If
		      Continue
		    End If
		    If line = "" Then Continue
		    If line.Left(1) = "#" Then
		      line = line.TrimLeft("#").Trim
		      If line <> "" Then Return line
		      Continue
		    End If
		    Return line
		  Next
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SlashCommands(projectPath As String) As String
		  Var result As String = "[" _
		  + "{""cmd"":""/compact"",""desc"":""Compact conversation history""}," _
		  + "{""cmd"":""/clear"",""desc"":""Clear conversation history""}," _
		  + "{""cmd"":""/review"",""desc"":""Review code changes""}," _
		  + "{""cmd"":""/memory"",""desc"":""Manage memory files""}," _
		  + "{""cmd"":""/init"",""desc"":""Initialize CLAUDE.md""}," _
		  + "{""cmd"":""/config"",""desc"":""View or edit configuration""}," _
		  + "{""cmd"":""/cost"",""desc"":""Show token usage and cost""}," _
		  + "{""cmd"":""/status"",""desc"":""Show account and system status""}"
		  
		  Var dirs() As FolderItem
		  Var globalCmds As FolderItem = SpecialFolder.UserHome.Child(".claude").Child("commands")
		  If globalCmds <> Nil And globalCmds.Exists Then dirs.Add(globalCmds)
		  If projectPath <> "" Then
		    Var projCmds As FolderItem = New FolderItem(projectPath, FolderItem.PathModes.Native)
		    If projCmds <> Nil Then projCmds = projCmds.Child(".claude").Child("commands")
		    If projCmds <> Nil And projCmds.Exists Then dirs.Add(projCmds)
		  End If
		  
		  Var seenCmds As New Dictionary
		  For Each dir As FolderItem In dirs
		    Var count As Integer = dir.Count
		    For i As Integer = 1 To count
		      Var f As FolderItem = dir.ChildAt(i - 1)
		      If f = Nil Or f.IsFolder Then Continue
		      If Not f.Name.EndsWith(".md") Then Continue
		      Var cmdName As String = "/" + f.Name.Left(f.Name.Length - 3)
		      If seenCmds.HasKey(cmdName) Then Continue
		      seenCmds.Value(cmdName) = True
		      Var desc As String = SkillDescription(f)
		      result = result + ",{""cmd"":" + DBHelper.JSONEscape(cmdName) + ",""desc"":" + DBHelper.JSONEscape(desc) + "}"
		    Next
		  Next
		  
		  Return result + "]"
		End Function
	#tag EndMethod



	#tag Property, Flags = &h21
		Private mCachedModelList As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mModelConn As URLConnection
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingDelegate As ChatView
	#tag EndProperty

	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
