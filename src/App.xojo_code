#tag Class
Protected Class App
Inherits DesktopApplication
	#tag Event
		Sub UnhandledException(error As RuntimeException)
		  Var msg As String = "Error: " + error.Message + EndOfLine
		  msg = msg + "Error Number: " + Str(error.ErrorNumber) + EndOfLine
		  If error.Stack <> Nil Then
		    msg = msg + "Stack:" + EndOfLine
		    For Each frame As String In error.Stack
		      msg = msg + "  " + frame + EndOfLine
		    Next
		  End If

		  // Best-effort write — if the log file can't be opened/created we
		  // swallow the I/O error so it doesn't mask the original exception.
		  AppendDebugLog(msg)
		End Sub
	#tag EndEvent

	#tag Event
		Sub Opening()
		  Var mbsReg() As String = Secrets.GetMBSRegistration()
		  If mbsReg(3) <> "" Then
		    If Not RegisterMBSPlugin(mbsReg(0).Trim, mbsReg(1).Trim, Integer.FromString(mbsReg(2).Trim), mbsReg(3).Trim) Then
		      System.DebugLog("MBS registration failed — check Owner/Product/Year/Key in keychain")
		    End If
		  Else
		    System.DebugLog("MBS serial not found — add to keychain: security add-generic-password -s MBS -a Key -w YOUR_KEY")
		  End If

		  Var projectPath As String = ""

		  Var projectFile As FolderItem = ChooseProjectFile
		  If projectFile <> Nil Then
		    ' Project path is the folder that contains the .xojo_project file —
		    ' git lookups expect a directory, not the file itself.
		    If projectFile.Parent <> Nil Then projectPath = projectFile.Parent.NativePath

		    ' Pull the target project's OSXBundleID. The external XMCP server uses
		    ' this to resolve /tmp/<bundle-id>_debug.log when get_debug_log fires.
		    RefreshTargetBundleId(projectFile)

		    ' Open the project in Xojo (launches the IDE if needed) and wait briefly
		    ' for the IPC socket to appear so XMCP can attach.
		    OpenInXojo(projectFile)
		    WaitForIDESocket(5000)

		    ' Xojo grabs focus when it opens; bring XMCPStudio back to the front.
		    RaiseSelf
		  End If

		  Var appSupport As FolderItem = AppSupportFolder
		  If Not appSupport.Exists Then appSupport.CreateFolder

		  Var dbFile As FolderItem = appSupport.Child("xmcpstudio.sqlite")
		  If Not dbFile.Exists Then
		    Var template As FolderItem = FindFile("xmcpstudio_template.sqlite")
		    If template <> Nil And template.Exists Then
		      template.CopyTo(dbFile)
		    Else
		      Var msg As String = "App: xmcpstudio_template.sqlite missing from Resources/ — Build Step not run."
		      System.DebugLog(msg)
		      AppendDebugLog(msg + EndOfLine)
		    End If
		  End If

		  Try
		    DBHelper.InitDB(dbFile)
		  Catch err As DatabaseException
		    Var msg As String = "Could not open the XMCPStudio database." + EndOfLine + EndOfLine _
		      + "Path: " + dbFile.NativePath + EndOfLine _
		      + "Reason: " + err.Message + EndOfLine + EndOfLine _
		      + "If the file is corrupt, quit XMCPStudio and move " + dbFile.Name + " aside — a fresh copy will be created on next launch."
		    System.DebugLog("App: DBHelper.InitDB failed: " + err.Message)
		    AppendDebugLog("App: DBHelper.InitDB failed: " + err.Message + EndOfLine)
		    MessageBox(msg)
		    Quit
		    Return
		  End Try

		  mProjectPath = projectPath

		  mCurrentTheme = DBHelper.GetSetting("theme", "system")

		  DBHelper.SeedProject(projectPath)

		  RegisterBackends()
		  Var savedBackend As String = DBHelper.GetSetting("active_backend", "Claude Code")
		  Var startPath As String = If(projectPath <> "", projectPath, SpecialFolder.UserHome.NativePath)
		  For Each b As AIBackend In mAvailableBackends
		    If b.Title = savedBackend Then
		      mActiveBackend = b
		      Exit
		    End If
		  Next
		  If mActiveBackend = Nil Then mActiveBackend = mAvailableBackends(0)
		  mActiveFrontend = FrontendForBackend(mActiveBackend)
		  mActiveBackend.SetDelegate(MainWindow.TheViewer)
		  mActiveBackend.Start(startPath)

		  RefreshGitBranch()
		End Sub
	#tag EndEvent

	#tag Method, Flags = &h0
		Sub OnWebViewReady()
		  MainWindow.TheViewer.RefreshJobs()
		  MainWindow.TheViewer.RefreshSessions()
		  MainWindow.TheViewer.RefreshNotes()
		  MainWindow.TheViewer.SetBackendStatus(mActiveBackend.Title, mActiveBackend.IsConnected, mActiveBackend.SupportsTools)
		  MainWindow.TheViewer.LoadBackends(GetBackendsJSON(), mActiveBackend.Title)
		  MainWindow.TheViewer.LoadBackendUI(BuildBackendUIConfig())
		  If mActiveFrontend IsA Claude.ClaudeFrontend Then
		    Claude.ClaudeFrontend(mActiveFrontend).FetchModelListAsync(MainWindow.TheViewer)
		  End If
		  MainWindow.TheViewer.SetProjectInfo(ProjectName(), mCurrentGitBranch)
		  MainWindow.TheViewer.ApplyTheme(mCurrentTheme)
		  UpdateWindowTitle()
		  WarnIfNoTargetBundleId()
		  mActiveBackend.FlushPendingError()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function CurrentTheme() As String
		  ' "system", "dark", or "light". Used by editor windows to inject the
		  ' current value when they open.
		  If mCurrentTheme = "" Then Return "system"
		  Return mCurrentTheme
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetTheme(theme As String)
		  ' Called from the status-bar select. Persists the choice and broadcasts
		  ' it to any open editor windows so they switch in lockstep with the
		  ' main window (which already applied the value locally via JS).
		  Var v As String = theme
		  If v <> "dark" And v <> "light" Then v = "system"
		  mCurrentTheme = v
		  DBHelper.SetSetting("theme", v)
		  BroadcastThemeToEditors(v)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub BroadcastThemeToEditors(theme As String)
		  ' Walks every open window and pokes the editor ones. Note/Job editors
		  ' both expose ApplyTheme on their EditorView.
		  For i As Integer = 0 To WindowCount - 1
		    Var w As DesktopWindow = Window(i)
		    If w IsA NoteEditorWindow Then
		      NoteEditorWindow(w).ApplyTheme(theme)
		    ElseIf w IsA JobEditorWindow Then
		      JobEditorWindow(w).ApplyTheme(theme)
		    ElseIf w IsA HelpWindow Then
		      HelpWindow(w).ApplyTheme(theme)
		    End If
		  Next
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub WarnIfNoTargetBundleId()
		  ' If the open project hasn't set OSXBundleID, get_debug_log won't have a
		  ' path to resolve. Surface that via a toast so the user can fix it in
		  ' Xojo (Build Settings → macOS → Bundle Identifier).
		  If mProjectPath = "" Then Return  ' no project picked yet
		  If mTargetBundleId <> "" Then Return
		  If MainWindow = Nil Or MainWindow.TheViewer = Nil Then Return
		  Var msg As String = "Heads up: this project has no OSXBundleID set. get_debug_log won't be able to find a crash log until you set one (Build Settings → macOS → Bundle Identifier in the Xojo IDE)."
		  MainWindow.TheViewer.EvaluateJavaScript("showToast(" + DBHelper.JSONEscape(msg) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ProjectName() As String
		  If mProjectPath = "" Then Return ""
		  Var f As New FolderItem(mProjectPath, FolderItem.PathModes.Native)
		  If f = Nil Then Return ""
		  Return f.Name
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub UpdateWindowTitle()
		  Var name As String = ProjectName()
		  If name = "" Then
		    MainWindow.Title = "XMCPStudio"
		  ElseIf mCurrentGitBranch = "" Or mCurrentGitBranch = "—" Then
		    MainWindow.Title = "XMCPStudio — " + name
		  Else
		    MainWindow.Title = "XMCPStudio — " + name + " (" + mCurrentGitBranch + ")"
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub HandleUserMessage(text As String)
		  MainWindow.TheViewer.ShowUserMessage(text)
		  Var history() As Dictionary
		  mActiveBackend.SendMessage(text, history)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub HandleUserMessageWithImage(text As String, imageBase64 As String, imageMediaType As String)
		  Var history() As Dictionary
		  mActiveBackend.SendMessageWithImage(text, imageBase64, imageMediaType, history)
		End Sub
	#tag EndMethod


	#tag Method, Flags = &h0
		Sub RefreshGitBranch()
		  mCurrentGitBranch = "—"
		  If mProjectPath = "" Then Return

		  // mProjectPath is the folder containing the .xojo_project file — run git
		  // directly on it, not on its parent.
		  Var sh As New Shell
		  sh.Execute("git -C " + ShellQuote(mProjectPath) + " rev-parse --abbrev-ref HEAD 2>/dev/null")
		  Var branch As String = sh.Result.Trim
		  If branch <> "" Then mCurrentGitBranch = branch
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ShellQuote(s As String) As String
		  ' POSIX-safe single-quote escape: 'foo' → 'foo', foo'bar → 'foo'\''bar'
		  Return "'" + s.ReplaceAll("'", "'\''") + "'"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function TargetBundleId() As String
		  ' Bundle ID of the Xojo project XMCPStudio is currently helping the user
		  ' debug — extracted from the open project's .xojo_project file at the
		  ' time the project was opened. Used by get_debug_log to find the right
		  ' /tmp/<bundle-id>_debug.log. Empty if no project is open, or if the
		  ' project file doesn't have an OSXBundleID line set.
		  Return mTargetBundleId
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub RefreshTargetBundleId(projectFile As FolderItem)
		  ' Called from App.Opening and SwitchProject. Parses OSXBundleID from
		  ' the .xojo_project file. .xojo_project and .xojo_xml_project are text;
		  ' .xojo_binary_project is binary and we can't read it that way.
		  mTargetBundleId = ""
		  If projectFile = Nil Or Not projectFile.Exists Then Return

		  Var fileName As String = projectFile.Name.Lowercase
		  If Not (fileName.EndsWith(".xojo_project") Or fileName.EndsWith(".xojo_xml_project")) Then
		    System.DebugLog("RefreshTargetBundleId: binary project format, can't extract OSXBundleID")
		    Return
		  End If

		  Try
		    Var ts As TextInputStream = TextInputStream.Open(projectFile)
		    ts.Encoding = Encodings.UTF8
		    Var allText As String = ts.ReadAll
		    ts.Close
		    Var idx As Integer = allText.IndexOf("OSXBundleID=")
		    If idx >= 0 Then
		      Var rest As String = allText.Middle(idx + 12)
		      Var nlIdx As Integer = rest.IndexOf(Chr(10))
		      If nlIdx < 0 Then
		        mTargetBundleId = rest.Trim
		      Else
		        mTargetBundleId = rest.Left(nlIdx).Trim
		      End If
		    End If
		  Catch e As IOException
		    System.DebugLog("RefreshTargetBundleId: read failed: " + e.Message)
		  End Try

		  If mTargetBundleId <> "" Then
		    System.DebugLog("RefreshTargetBundleId: target project bundle id found")
		  Else
		    System.DebugLog("RefreshTargetBundleId: target project bundle id missing")
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Shared Sub AppendDebugLog(msg As String)
		  ' Best-effort append to an app-private log file. Swallows I/O errors so
		  ' a failing log write can't mask the original exception that's being
		  ' reported. Appends rather than overwrites so multiple crashes in one
		  ' session don't lose prior diagnostics.
		  Try
		    Var f As FolderItem = DebugLogFile
		    If f = Nil Then Return
		    Var stream As TextOutputStream
		    If f.Exists Then
		      stream = TextOutputStream.Append(f)
		    Else
		      stream = TextOutputStream.Create(f)
		    End If
		    If stream <> Nil Then
		      stream.Write(msg)
		      stream.Close
		    End If
		  Catch e As RuntimeException
		    ' Intentionally swallowed — the caller is usually already in an
		    ' error-handling context, and a write failure here is less important
		    ' than not crashing again.
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function AppSupportFolder() As FolderItem
		  Var modern As FolderItem = SpecialFolder.ApplicationData.Child("dk.xmcpstudio")
		  Var legacy As FolderItem = SpecialFolder.ApplicationData.Child("dk.o3jvind.xmcpstudio")
		  If legacy <> Nil And legacy.Exists And (modern = Nil Or Not modern.Exists) Then Return legacy
		  Return modern
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function DebugLogFile() As FolderItem
		  Var appSupport As FolderItem = AppSupportFolder
		  If appSupport = Nil Then Return Nil
		  If Not appSupport.Exists Then appSupport.CreateFolder
		  Var bundleId As String = SelfBundleId
		  If bundleId = "" Then bundleId = "xmcpstudio"
		  bundleId = bundleId.ReplaceAll(".", "_")
		  Return appSupport.Child(bundleId + "_debug.log")
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function SelfBundleId() As String
		  ' Read the running app's CFBundleIdentifier from NSBundle.mainBundle.
		  ' Works without hardcoding, so anyone who rebuilds with a different
		  ' bundle ID still gets the right log path.
		  #If TargetMacOS Then
		    Declare Function NSClassFromString Lib "AppKit" (className As CFStringRef) As Ptr
		    Declare Function mainBundle Lib "AppKit" Selector "mainBundle" (NSBundleClass As Ptr) As Ptr
		    Declare Function bundleIdentifier Lib "AppKit" Selector "bundleIdentifier" (NSBundleRef As Ptr) As CFStringRef
		    Return bundleIdentifier(mainBundle(NSClassFromString("NSBundle")))
		  #Else
		    Return ""
		  #EndIf
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindProjectFiles(folder As FolderItem) As FolderItem()
		  ' Returns every Xojo project file (any of the three formats) directly inside folder.
		  Var result() As FolderItem
		  If folder = Nil Or Not folder.Exists Or Not folder.IsFolder Then Return result

		  Var count As Integer = folder.Count
		  For i As Integer = 0 To count - 1
		    Var f As FolderItem = folder.ChildAt(i)
		    If f = Nil Or f.IsFolder Then Continue
		    Var name As String = f.Name.Lowercase
		    If name.EndsWith(".xojo_project") _
		      Or name.EndsWith(".xojo_xml_project") _
		      Or name.EndsWith(".xojo_binary_project") Then
		      result.Add(f)
		    End If
		  Next
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ChooseProjectFile() As FolderItem
		  ' Loops until the user picks a folder containing a valid Xojo project,
		  ' or cancels (returns Nil). Handles single, multiple, and zero-project cases.
		  While True
		    Var dlg As New SelectFolderDialog
		    dlg.Title = "Choose project folder for XMCPStudio"
		    Var chosen As FolderItem = dlg.ShowModal
		    If chosen = Nil Then Return Nil  ' user cancelled

		    Var candidates() As FolderItem = FindProjectFiles(chosen)

		    If candidates.Count = 0 Then
		      Var msg As New MessageDialog
		      msg.Message = "No Xojo project found"
		      msg.Explanation = "The folder " + chosen.Name + " doesn't contain a .xojo_project file. Choose a different folder."
		      msg.ActionButton.Caption = "Choose Again"
		      msg.CancelButton.Visible = True
		      msg.CancelButton.Caption = "Cancel"
		      Var btn As MessageDialogButton = msg.ShowModalWithin(Nil)
		      If btn Is msg.CancelButton Then Return Nil
		      Continue  ' re-show the folder picker
		    End If

		    If candidates.Count = 1 Then Return candidates(0)

		    ' 2+ candidates → show the picker window.
		    Var picker As New ProjectPickerWindow
		    Var picked As FolderItem = picker.PickFrom(candidates)
		    If picked <> Nil Then Return picked
		    ' User cancelled the picker — loop back to folder selection.
		  Wend
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub OpenInXojo(projectFile As FolderItem)
		  ' Asks macOS to open the project file with Xojo. Launches Xojo if it's not
		  ' running; brings it to the front if it is.
		  If projectFile = Nil Or Not projectFile.Exists Then Return
		  Var sh As New Shell
		  sh.Execute("open -a Xojo " + ShellQuote(projectFile.NativePath))
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub WaitForIDESocket(timeoutMS As Integer)
		  ' Polls /tmp/XojoIDE until it appears or the timeout expires.
		  ' The IPC socket is created by the Xojo IDE only after a project is loaded.
		  Var socketFile As New FolderItem("/tmp/XojoIDE", FolderItem.PathModes.Native)
		  Var deadline As Double = System.Microseconds + (timeoutMS * 1000.0)
		  While System.Microseconds < deadline
		    If socketFile.Exists Then Return
		    App.DoEvents(50)
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub RaiseSelf()
		  ' Brings XMCPStudio back to the foreground after Xojo grabs focus on open.
		  ' Uses our own executable path so this works in debug builds too
		  ' (where the bundle name is XMCPStudio.debug.app rather than XMCPStudio.app).
		  Var exe As FolderItem = App.ExecutableFile
		  If exe = Nil Then Return
		  ' Walk up MacOS/<Exe> → Contents → <Bundle>.app
		  Var bundle As FolderItem = exe.Parent
		  If bundle <> Nil Then bundle = bundle.Parent
		  If bundle = Nil Then Return
		  Var sh As New Shell
		  sh.Execute("open " + ShellQuote(bundle.NativePath))
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ActiveBackend() As AIBackend
		  Return mActiveBackend
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetBackendModel(model As String)
		  mActiveBackend.SetModel(model)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetBackendMode(mode As String)
		  mActiveBackend.SetMode(mode)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetBackendEffort(effort As String)
		  mActiveBackend.SetReasoningEffort(effort)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetApprovalMode(mode As String)
		  If Not (mActiveBackend IsA Codex.CodexBackend) Then Return
		  Var dx As Codex.CodexBackend = Codex.CodexBackend(mActiveBackend)
		  dx.SetAutoApprove(mode = "auto")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ExportCurrentSession()
		  ' File → Export Session as Markdown… handler.
		  ' Reads the active session's parsed messages and writes them to a user-chosen .md file.

		  If mActiveBackend.SessionId = "" Then
		    Var msg As New MessageDialog
		    msg.Message = "No active session yet"
		    msg.Explanation = "Send at least one message before exporting. XMCPStudio doesn't have a session UUID to read until the AI has initialized."
		    msg.ActionButton.Caption = "OK"
		    Call msg.ShowModalWithin(Nil)
		    Return
		  End If

		  Var uuid As String = mActiveBackend.SessionId
		  Var jsonArray As String = mActiveBackend.GetSessionChatJSON(uuid)
		  If jsonArray = "[]" Or jsonArray = "" Then
		    Var msg As New MessageDialog
		    msg.Message = "Session has no exportable messages"
		    msg.Explanation = "The session log exists but contains no user or assistant turns yet."
		    msg.ActionButton.Caption = "OK"
		    Call msg.ShowModalWithin(Nil)
		    Return
		  End If

		  Var markdown As String = FormatSessionAsMarkdown(jsonArray, uuid)

		  ' Build a sensible default filename: <project>-<YYYY-MM-DD>-<uuid8>.md
		  Var today As Date = New Date
		  Var dateStr As String = today.Year.ToString + "-" _
		    + If(today.Month < 10, "0", "") + today.Month.ToString + "-" _
		    + If(today.Day < 10, "0", "") + today.Day.ToString
		  Var projName As String = ProjectName()
		  If projName = "" Then projName = "session"
		  Var defaultName As String = projName + "-" + dateStr + "-" + uuid.Left(8) + ".md"

		  Var dlg As New SaveFileDialog
		  dlg.Title = "Export Session as Markdown"
		  dlg.SuggestedFileName = defaultName
		  Var f As FolderItem = dlg.ShowModal
		  If f = Nil Then Return  ' user cancelled

		  Try
		    Var ts As TextOutputStream = TextOutputStream.Create(f)
		    ts.Encoding = Encodings.UTF8
		    ts.Write(markdown)
		    ts.Close
		  Catch e As IOException
		    Var msg As New MessageDialog
		    msg.Message = "Could not write the file"
		    msg.Explanation = e.Message
		    msg.ActionButton.Caption = "OK"
		    Call msg.ShowModalWithin(Nil)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FormatSessionAsMarkdown(jsonArray As String, uuid As String) As String
		  ' Converts a [{role, content}, ...] JSON array (from GetSessionChatJSON)
		  ' into a readable Markdown document with per-turn headings and dividers.

		  Var today As Date = New Date
		  Var dateStr As String = today.Year.ToString + "-" _
		    + If(today.Month < 10, "0", "") + today.Month.ToString + "-" _
		    + If(today.Day < 10, "0", "") + today.Day.ToString

		  Var projName As String = ProjectName()
		  If projName = "" Then projName = "(no project)"

		  Var out As String = "# Conversation — " + dateStr + " — " + projName + EndOfLine + EndOfLine
		  out = out + "_Session: " + uuid + "_" + EndOfLine + EndOfLine + "---" + EndOfLine + EndOfLine

		  Try
		    Var arr As New JSONItem(jsonArray)
		    Var n As Integer = arr.Count
		    For i As Integer = 0 To n - 1
		      Var msg As JSONItem = arr.ChildAt(i)
		      Var role As String = If(msg.HasKey("role"), msg.Value("role").StringValue, "")
		      Var content As String = If(msg.HasKey("content"), msg.Value("content").StringValue, "")
		      If role = "" Or content = "" Then Continue

		      Var heading As String
		      If role = "user" Then
		        heading = "## User"
		      ElseIf role = "assistant" Then
		        heading = "## Assistant"
		      Else
		        heading = "## " + role
		      End If

		      out = out + heading + EndOfLine + EndOfLine + content + EndOfLine + EndOfLine + "---" + EndOfLine + EndOfLine
		    Next
		  Catch e As JSONException
		    out = out + "_(Could not parse session JSON: " + e.Message + ")_" + EndOfLine
		  End Try

		  Return out
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ResumeSession(uuid As String)
		  mActiveBackend.ResumeSession(uuid)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub NewSession()
		  mActiveBackend.NewSession()
		  MainWindow.TheViewer.ClearChat()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SwitchProject()
		  ' Triggered by File → Open Project…. Lets the user pick a different
		  ' Xojo project, opens it in Xojo, and restarts the Claude bridge so
		  ' Claude's workspaceFolders reflect the new project.
		  Var projectFile As FolderItem = ChooseProjectFile
		  If projectFile = Nil Then Return  ' user cancelled

		  Var newPath As String = ""
		  If projectFile.Parent <> Nil Then newPath = projectFile.Parent.NativePath

		  ' Pull the new target project's OSXBundleID — get_debug_log resolves
		  ' /tmp/<bundle-id>_debug.log from this value.
		  RefreshTargetBundleId(projectFile)

		  ' Open the project in Xojo and wait briefly for the IPC socket.
		  OpenInXojo(projectFile)
		  WaitForIDESocket(5000)
		  RaiseSelf

		  mProjectPath = newPath

		  SeedProject(newPath)

		  mActiveBackend.SessionId = ""
		  mActiveBackend.Shutdown()
		  mActiveBackend.Start(If(newPath <> "", newPath, SpecialFolder.UserHome.NativePath))

		  ' Refresh UI.
		  RefreshGitBranch
		  If MainWindow.TheViewer.IsReady Then
		    MainWindow.TheViewer.ClearChat
		    MainWindow.TheViewer.RefreshSessions
		    MainWindow.TheViewer.RefreshNotes
		    MainWindow.TheViewer.SetProjectInfo(ProjectName(), mCurrentGitBranch)
		    MainWindow.TheViewer.SetBackendStatus(mActiveBackend.Title, mActiveBackend.IsConnected, mActiveBackend.SupportsTools)
		  End If
		  UpdateWindowTitle
		  WarnIfNoTargetBundleId
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub PendXmcpMessage(text As String)
		  mPendingXmcpMessage = text
		  MainWindow.TheViewer.ShowPermissionPrompt(text, "")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub GrantPermission(path As String, always As Boolean)
		  #Pragma Unused path
		  If mActiveBackend IsA Claude.ClaudeCodeBackend Then
		    Var cb As Claude.ClaudeCodeBackend = Claude.ClaudeCodeBackend(mActiveBackend)
		    If mPendingXmcpMessage <> "" Then
		      Var msg As String = mPendingXmcpMessage
		      mPendingXmcpMessage = ""
		      HandleUserMessage(msg)
		    Else
		      cb.SendControlResponse(True)
		      If always Then
		        cb.SetAutoApprove(True)
		        MainWindow.TheViewer.SetModeSelect("auto")
		      End If
		    End If
		  ElseIf mActiveBackend IsA Codex.CodexBackend Then
		    Var dx As Codex.CodexBackend = Codex.CodexBackend(mActiveBackend)
		    dx.SendApprovalResponse(True, always)
		    If always Then
		      dx.SetAutoApprove(True)
		      MainWindow.TheViewer.SetApprovalSelect("auto")
		    End If
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub DenyPermission()
		  If mActiveBackend IsA Claude.ClaudeCodeBackend Then
		    If mPendingXmcpMessage <> "" Then
		      mPendingXmcpMessage = ""
		    Else
		      Var cb As Claude.ClaudeCodeBackend = Claude.ClaudeCodeBackend(mActiveBackend)
		      cb.SendControlResponse(False)
		    End If
		  ElseIf mActiveBackend IsA Codex.CodexBackend Then
		    Var dx As Codex.CodexBackend = Codex.CodexBackend(mActiveBackend)
		    dx.SendApprovalResponse(False)
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ApprovePlan()
		  Var cb As Claude.ClaudeCodeBackend = Claude.ClaudeCodeBackend(mActiveBackend)
		  If cb = Nil Then Return
		  cb.ApprovePlan()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub RejectPlan()
		  Var cb As Claude.ClaudeCodeBackend = Claude.ClaudeCodeBackend(mActiveBackend)
		  If cb = Nil Then Return
		  cb.RejectPlan()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub AnswerUserQuestion(answersJSON As String)
		  Var cb As Claude.ClaudeCodeBackend = Claude.ClaudeCodeBackend(mActiveBackend)
		  If cb = Nil Then Return
		  cb.AnswerUserQuestion(answersJSON)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FrontendForBackend(backend As AIBackend) As AIFrontend
		  Var idx As Integer = -1
		  Var i As Integer
		  For i = 0 To mAvailableBackends.LastRowIndex
		    If mAvailableBackends(i) Is backend Then
		      idx = i
		      Exit
		    End If
		  Next
		  If idx >= 0 And idx <= mAvailableFrontends.LastRowIndex Then
		    Return mAvailableFrontends(idx)
		  End If
		  Return New AIFrontend
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub RegisterBackends()
		  mAvailableBackends.RemoveAll()
		  mAvailableBackends.Add(New Claude.ClaudeCodeBackend)
		  mAvailableBackends.Add(New Codex.CodexBackend)
		  mAvailableFrontends.RemoveAll()
		  mAvailableFrontends.Add(New Claude.ClaudeFrontend)
		  mAvailableFrontends.Add(New Codex.CodexFrontend)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SwitchBackend(title As String)
		  Var target As AIBackend
		  For Each b As AIBackend In mAvailableBackends
		    If b.Title = title Then
		      target = b
		      Exit
		    End If
		  Next
		  If target = Nil Or target Is mActiveBackend Then Return

		  mActiveBackend.Shutdown()
		  mActiveBackend = target
		  mActiveFrontend = FrontendForBackend(target)
		  DBHelper.SetSetting("active_backend", title)
		  mActiveBackend.SetDelegate(MainWindow.TheViewer)
		  mActiveBackend.Start(If(mProjectPath <> "", mProjectPath, SpecialFolder.UserHome.NativePath))

		  If MainWindow.TheViewer.IsReady Then
		    MainWindow.TheViewer.ClearChat()
		    MainWindow.TheViewer.SetBackendStatus(mActiveBackend.Title, mActiveBackend.IsConnected, mActiveBackend.SupportsTools)
		    MainWindow.TheViewer.LoadBackends(GetBackendsJSON(), title)
		    MainWindow.TheViewer.LoadBackendUI(BuildBackendUIConfig())
		    If mActiveFrontend IsA Claude.ClaudeFrontend Then
		      Claude.ClaudeFrontend(mActiveFrontend).FetchModelListAsync(MainWindow.TheViewer)
		    End If
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function BuildBackendUIConfig() As String
		  Var b As AIBackend = mActiveBackend
		  Var f As AIFrontend = mActiveFrontend

		  Var modelsArr As String = f.ModelList()
		  If modelsArr = "[]" Then
		    modelsArr = "["
		    Var mFirst As Boolean = True
		    For Each m As String In b.Models
		      If Not mFirst Then modelsArr = modelsArr + ","
		      mFirst = False
		      modelsArr = modelsArr + "{""value"":" + DBHelper.JSONEscape(m) + ",""label"":" + DBHelper.JSONEscape(m) + "}"
		    Next
		    modelsArr = modelsArr + "]"
		  End If

		  Var effortOpts As String
		  If b IsA Claude.ClaudeCodeBackend Then
		    effortOpts = "[{""value"":""low"",""label"":""Low""},{""value"":""medium"",""label"":""Medium""},{""value"":""high"",""label"":""High""},{""value"":""xhigh"",""label"":""X-High""},{""value"":""max"",""label"":""Max""}]"
		  Else
		    effortOpts = "[{""value"":""low"",""label"":""Low""},{""value"":""medium"",""label"":""Medium""},{""value"":""high"",""label"":""High""}]"
		  End If

		  Return "{" _
		    + """models"":" + modelsArr + "," _
		    + """defaultModel"":" + DBHelper.JSONEscape(b.DefaultModel) + "," _
		    + """capabilities"":{" _
		      + """supportsPlanMode"":" + If(b.SupportsPlanMode, "true", "false") + "," _
		      + """supportsImageInput"":" + If(b.SupportsImageInput, "true", "false") + "," _
		      + """supportsPermissionPrompts"":" + If(b.SupportsPermissionPrompts, "true", "false") + "," _
		      + """supportsReasoningEffort"":" + If(b.SupportsReasoningEffort, "true", "false") _
		    + "}," _
		    + """effortOptions"":" + effortOpts + "," _
		    + """slashCommands"":" + f.SlashCommands(mProjectPath) + "," _
		    + """modeOptions"":" + f.ModeOptions() + "," _
		    + """toolbarItems"":" + f.ToolbarItems() + "," _
		    + """supportsXMCP"":" + If(f.SupportsXMCP(), "true", "false") + "," _
		    + """sessions"":" + f.SessionList(mProjectPath) _
		    + "}"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetBackendsJSON() As String
		  Var result As String = "["
		  Var first As Boolean = True
		  For Each b As AIBackend In mAvailableBackends
		    If Not first Then result = result + ","
		    first = False
		    result = result + DBHelper.JSONEscape(b.Title)
		  Next
		  Return result + "]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionsJSON() As String
		  Return mActiveFrontend.SessionList(mProjectPath)
		End Function
	#tag EndMethod



	#tag Method, Flags = &h0
		Function CurrentProjectPath() As String
		  Return mProjectPath
		End Function
	#tag EndMethod


	#tag Method, Flags = &h0
		Function FindFile(name As String) As FolderItem
		  Var f As FolderItem

		  ' Split name on "/" and descend step by step
		  Var parts() As String = name.Split("/")

		  Dim roots(3) As FolderItem
		  roots(0) = App.ExecutableFile.Parent
		  roots(1) = App.ExecutableFile.Parent.Parent.Child("Resources")
		  roots(2) = App.ExecutableFile.Parent.Parent.Parent.Parent.Child("src")  ' debug: MacOS -> Contents -> .app -> src
		  roots(3) = App.ExecutableFile.Parent.Parent.Parent.Parent.Parent.Child("src")  ' built: MacOS -> Contents -> .app -> Builds -> src

		  For i As Integer = 0 To 3
		    f = roots(i)
		    If f = Nil Then Continue
		    For Each part As String In parts
		      f = f.Child(part)
		      If f = Nil Then Exit
		    Next
		    If f <> Nil And f.Exists Then Return f
		  Next

		  System.DebugLog("FindFile: not found: " + name)
		  Return Nil
		End Function
	#tag EndMethod

	#tag Constant, Name = kEditClear, Type = String, Dynamic = False, Default = "&Delete", Scope = Public
		#Tag Instance, Platform = Windows, Language = Default, Definition  = "&Delete"
		#Tag Instance, Platform = Linux, Language = Default, Definition  = "&Delete"
	#tag EndConstant

	#tag Constant, Name = kFileQuit, Type = String, Dynamic = False, Default = "&Quit", Scope = Public
		#Tag Instance, Platform = Windows, Language = Default, Definition  = "E&xit"
	#tag EndConstant

	#tag Constant, Name = kFileQuitShortcut, Type = String, Dynamic = False, Default = "", Scope = Public
		#Tag Instance, Platform = Mac OS, Language = Default, Definition  = "Cmd+Q"
		#Tag Instance, Platform = Linux, Language = Default, Definition  = "Ctrl+Q"
	#tag EndConstant

	#tag Property, Flags = &h21
		Private mActiveBackend As AIBackend
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mActiveFrontend As AIFrontend
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAvailableBackends() As AIBackend
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAvailableFrontends() As AIFrontend
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mProjectPath As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCurrentGitBranch As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mTargetBundleId As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCurrentTheme As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingXmcpMessage As String
	#tag EndProperty

End Class
#tag EndClass
