#tag Class
Protected Class ChatView
Inherits DesktopWKWebViewControlMBS
Implements AIBackendDelegate
	#tag Event
		Sub didReceiveScriptMessage(Body as Variant, name as String)
		  Select Case name
		    
		  Case "ready"
		    mIsReady = True
		    System.DebugLog("ChatView: JS ready")
		    App.OnWebViewReady()
		    
		  Case "sendMessage"
		    Var dict As Dictionary = Body
		    Var text As String = dict.Lookup("text", "")
		    Var imageBase64 As String = dict.Lookup("imageBase64", "")
		    Var imageMediaType As String = dict.Lookup("imageMediaType", "")
		    If imageBase64 <> "" Then
		      Var dataUrl As String = "data:" + imageMediaType + ";base64," + imageBase64
		      Me.EvaluateJavaScript("showUserMessage(" + DBHelper.JSONEscape(text) + ", " + DBHelper.JSONEscape(dataUrl) + ");")
		      App.HandleUserMessageWithImage(text, imageBase64, imageMediaType)
		    ElseIf text <> "" Then
		      App.HandleUserMessage(text)
		    End If
		    
		  Case "xmcpAction"
		    Var xaDict As Dictionary = Body
		    Var xaMsg As String = xaDict.Lookup("message", "")
		    Var xaMode As String = xaDict.Lookup("mode", "auto")
		    If xaMsg = "" Then Return
		    If App.ActiveBackend IsA Claude.ClaudeCodeBackend Then
		      App.PendXmcpMessage(xaMsg)
		    Else
		      App.HandleUserMessage(xaMsg)
		    End If

		  Case "openJobEditor"
		    Var ojDict As Dictionary = Body
		    Var jid As Integer = ojDict.Lookup("id", 0)
		    Var jwin As New JobEditorWindow
		    If jid > 0 Then
		      Var j As Dictionary = DBHelper.GetJobById(jid)
		      jwin.LoadJob(jid, _
		        j.Lookup("name", ""), _
		        j.Lookup("prompt", ""), _
		        j.Lookup("description", ""), _
		        j.Lookup("tags", ""))
		    Else
		      ' New job — accept optional prefill from JS (used by "Copy" action).
		      jwin.LoadJob(0, _
		        ojDict.Lookup("name", ""), _
		        ojDict.Lookup("prompt", ""), _
		        ojDict.Lookup("description", ""), _
		        ojDict.Lookup("tags", ""))
		    End If
		    jwin.Show

		  Case "insertJobPrompt"
		    Var ipDict As Dictionary = Body
		    Var promptStr As String = ipDict.Lookup("prompt", "")
		    Var insDlg As New MessageDialog
		    insDlg.Message = "The chat input already has text."
		    insDlg.Explanation = "Append the job prompt on a new line, or overwrite the current text?"
		    insDlg.ActionButton.Caption = "Append"
		    insDlg.AlternateActionButton.Visible = True
		    insDlg.AlternateActionButton.Caption = "Overwrite"
		    insDlg.CancelButton.Visible = True
		    insDlg.CancelButton.Caption = "Cancel"
		    Var insBtn As MessageDialogButton = insDlg.ShowModal
		    If insBtn = insDlg.ActionButton Then
		      Me.EvaluateJavaScript("appendToInput(" + DBHelper.JSONEscape(promptStr) + ");")
		    ElseIf insBtn = insDlg.AlternateActionButton Then
		      Me.EvaluateJavaScript("overwriteInput(" + DBHelper.JSONEscape(promptStr) + ");")
		    End If
		    
		    
		  Case "deleteJob"
		    Var dict As Dictionary = Body
		    ' Only refresh on success: a failed delete leaves the row in place,
		    ' and refreshing would otherwise hide a row that still exists.
		    If DBHelper.DeleteJob(dict.Lookup("id", 0)) Then RefreshJobs()


		  Case "createNote"
		    Var dict As Dictionary = Body
		    Var ok As Boolean = DBHelper.CreateNote( _
		      dict.Lookup("title", ""), _
		      dict.Lookup("body", ""), _
		      dict.Lookup("tags", ""), _
		      dict.Lookup("description", ""), _
		      dict.Lookup("scope", "global"), _
		      App.CurrentProjectPath())
		    If ok Then RefreshNotes()

		  Case "editNote"
		    Var dict As Dictionary = Body
		    Var ok As Boolean = DBHelper.UpdateNote( _
		      dict.Lookup("id", 0), _
		      dict.Lookup("title", ""), _
		      dict.Lookup("body", ""), _
		      dict.Lookup("tags", ""), _
		      dict.Lookup("description", ""), _
		      dict.Lookup("scope", "global"), _
		      App.CurrentProjectPath())
		    If ok Then RefreshNotes()

		  Case "deleteNote"
		    Var dict As Dictionary = Body
		    If DBHelper.DeleteNote(dict.Lookup("id", 0)) Then RefreshNotes()

		  Case "reorderNote"
		    ' Reorder is different: JS does not reorder the DOM locally, so we always
		    ' refresh — on success to show the new order, on failure to undo any
		    ' optimistic state (currently none, but kept for symmetry with future JS).
		    Var dict As Dictionary = Body
		    Call DBHelper.ReorderNote(dict.Lookup("fromId", 0), dict.Lookup("toId", 0))
		    RefreshNotes()
		    
		  Case "diffAccepted"
		    Var dict As Dictionary = Body
		    App.ActiveBackend.OnDiffAccepted(dict.Lookup("requestId", ""), dict.Lookup("filePath", ""))
		    
		  Case "diffRejected"
		    Var dict As Dictionary = Body
		    App.ActiveBackend.OnDiffRejected(dict.Lookup("requestId", ""))
		    
		  Case "stopGeneration"
		    App.ActiveBackend.StopGeneration()
		    
		  Case "reorderJob"
		    ' See note above on reorderNote: always refresh.
		    Var dict As Dictionary = Body
		    Call DBHelper.ReorderJob(dict.Lookup("fromId", 0), dict.Lookup("toId", 0))
		    RefreshJobs()

		  Case "newSession"
		    App.NewSession()
		    RefreshSessions()

		  Case "selectSession"
		    Var dict As Dictionary = Body
		    Var uuid As String = dict.Lookup("uuid", "")
		    If uuid <> "" Then
		      App.ResumeSession(uuid)
		      Var chatJSON As String = App.ActiveBackend.GetSessionChatJSON(uuid)
		      Me.EvaluateJavaScript("loadSessionChat(" + chatJSON + ");")
		    End If

		  Case "clearChat"
		    ' UI cleared in JS; no DB action needed

		  Case "setBackend"
		    Var sbDict As Dictionary = Body
		    App.SwitchBackend(sbDict.Lookup("backend", ""))

		  Case "setModel"
		    Var smDict As Dictionary = Body
		    App.SetBackendModel(smDict.Lookup("model", ""))

		  Case "setMode"
		    Var sdDict As Dictionary = Body
		    App.SetBackendMode(sdDict.Lookup("mode", ""))

		  Case "setApprovalMode"
		    Var saDict As Dictionary = Body
		    App.SetApprovalMode(saDict.Lookup("mode", "ask"))

		  Case "setEffort"
		    Var seDict As Dictionary = Body
		    App.SetBackendEffort(seDict.Lookup("effort", "medium"))

		  Case "setTheme"
		    Var stDict As Dictionary = Body
		    App.SetTheme(stDict.Lookup("theme", "system"))

		  Case "compactHistory"
		    App.HandleUserMessage("/compact")

		  Case "pickFile"
		    Var dlg As New OpenFileDialog
		    Var picked As FolderItem = dlg.ShowModal
		    If picked <> Nil Then
		      Me.EvaluateJavaScript("insertText(" + DBHelper.JSONEscape(picked.NativePath) + ");")
		    End If

		  Case "grantPermission"
		    Var gpDict As Dictionary = Body
		    App.GrantPermission(gpDict.Lookup("path", ""), gpDict.Lookup("always", False))

		  Case "denyPermission"
		    Me.EvaluateJavaScript("showToast('Permission denied — operation cancelled.');")
		    App.DenyPermission()

		  Case "approvePlan"
		    App.ApprovePlan()

		  Case "rejectPlan"
		    App.RejectPlan()

		  Case "askUserAnswer"
		    Var auqDict As Dictionary = Body
		    Var answersJSON As String = auqDict.Lookup("answersJSON", "{}")
		    App.AnswerUserQuestion(answersJSON)

		  Case "openNote"
		    Var onDict As Dictionary = Body
		    Var win As New NoteEditorWindow
		    win.LoadNote( _
		      onDict.Lookup("id", 0), _
		      onDict.Lookup("title", ""), _
		      onDict.Lookup("body", ""), _
		      onDict.Lookup("tags", ""), _
		      onDict.Lookup("description", ""), _
		      onDict.Lookup("scope", "global"))
		    win.Show

		  Case "openURL"
		    Var urlStr As String = Body.StringValue
		    If urlStr.Left(7) = "http://" Or urlStr.Left(8) = "https://" Then
		      ShowURL(urlStr)
		    End If

		  End Select
		End Sub
	#tag EndEvent

	#tag Event
		Sub Opening()
		  #If DebugBuild Then
		    Me.developerExtrasEnabled = True
		  #EndIf
		  Me.AddScriptMessageHandler("ready")
		  Me.AddScriptMessageHandler("sendMessage")
		  Me.AddScriptMessageHandler("openJobEditor")
		  Me.AddScriptMessageHandler("insertJobPrompt")
		  Me.AddScriptMessageHandler("deleteJob")
		  Me.AddScriptMessageHandler("reorderJob")
		  Me.AddScriptMessageHandler("createNote")
		  Me.AddScriptMessageHandler("editNote")
		  Me.AddScriptMessageHandler("deleteNote")
		  Me.AddScriptMessageHandler("reorderNote")
		  Me.AddScriptMessageHandler("diffAccepted")
		  Me.AddScriptMessageHandler("diffRejected")
		  Me.AddScriptMessageHandler("stopGeneration")
		  Me.AddScriptMessageHandler("newSession")
		  Me.AddScriptMessageHandler("selectSession")
		  Me.AddScriptMessageHandler("clearChat")
		  Me.AddScriptMessageHandler("setBackend")
		  Me.AddScriptMessageHandler("setModel")
		  Me.AddScriptMessageHandler("setMode")
		  Me.AddScriptMessageHandler("setApprovalMode")
		  Me.AddScriptMessageHandler("setEffort")
		  Me.AddScriptMessageHandler("setTheme")
		  Me.AddScriptMessageHandler("compactHistory")
		  Me.AddScriptMessageHandler("pickFile")
		  Me.AddScriptMessageHandler("grantPermission")
		  Me.AddScriptMessageHandler("denyPermission")
		  Me.AddScriptMessageHandler("approvePlan")
		  Me.AddScriptMessageHandler("rejectPlan")
		  Me.AddScriptMessageHandler("askUserAnswer")
		  Me.AddScriptMessageHandler("openNote")
		  Me.AddScriptMessageHandler("xmcpAction")
  Me.AddScriptMessageHandler("openURL")
		End Sub
	#tag EndEvent


	#tag Method, Flags = &h0
		Sub HandleImageDrop(f As FolderItem)
		  Try
		    Var bs As BinaryStream = BinaryStream.Open(f, False)
		    Var data As String = bs.Read(bs.Length)
		    bs.Close
		    Var ext As String = f.Name.NthField(".", f.Name.CountFields(".")).Lowercase
		    Var mediaType As String
		    Select Case ext
		    Case "jpg", "jpeg"
		      mediaType = "image/jpeg"
		    Case "gif"
		      mediaType = "image/gif"
		    Case "webp"
		      mediaType = "image/webp"
		    Else
		      mediaType = "image/png"
		    End Select
		    Var b64 As String = EncodeBase64(data).ReplaceAll(Chr(13), "").ReplaceAll(Chr(10), "")
		    Me.EvaluateJavaScript("insertImageAttachment(" + DBHelper.JSONEscape(f.Name) + ", " + DBHelper.JSONEscape(b64) + ", " + DBHelper.JSONEscape(mediaType) + ");")
		  Catch e As RuntimeException
		    System.DebugLog("ChatView.HandleImageDrop error: " + e.Message)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub AppendToken(token As String)
		  Me.EvaluateJavaScript("appendToken(" + DBHelper.JSONEscape(token) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub FinalizeMessage()
		  Me.EvaluateJavaScript("finalizeMessage();")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowError(msg As String)
		  Me.EvaluateJavaScript("showError(" + DBHelper.JSONEscape(msg) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function LoadCSSFiles() As String
		  Var files() As String = Array( _
		  "web-assets/css/variables.css", _
		  "web-assets/css/layout.css", _
		  "web-assets/css/chat.css", _
		  "web-assets/css/sidebar.css", _
		  "web-assets/css/modals.css")
		  Var result As String
		  For Each f As String In files
		    result = result + LoadFileContent(f) + EndOfLine
		  Next
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function LoadFileContent(relativePath As String) As String
		  Var f As FolderItem = App.FindFile(relativePath)
		  If f = Nil Or Not f.Exists Then
		    System.DebugLog("ChatView: file not found: " + relativePath)
		    Return ""
		  End If
		  Var ts As TextInputStream = TextInputStream.Open(f)
		  ts.Encoding = Encodings.UTF8
		  Var content As String = ts.ReadAll
		  ts.Close
		  Return content
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function LoadJSFiles() As String
		  Var files() As String = Array( _
		  "web-assets/js/vendor/marked.min.js", _
		  "web-assets/js/sanitize.js", _
		  "web-assets/js/main.js", _
		  "web-assets/js/chat-handler.js", _
		  "web-assets/js/job-manager.js", _
		  "web-assets/js/notes-manager.js")
		  Var result As String
		  For Each f As String In files
		    result = result + LoadFileContent(f) + EndOfLine
		  Next
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub LoadUI()
		  Var resourcesFolder As FolderItem = App.ExecutableFile.Parent.Parent.Child("Resources")
		  Var baseURL As String = "file://" + resourcesFolder.NativePath + "/"
		  
		  Try
		    Var html As String = LoadFileContent("web-assets/index.html")
		    If html.Length = 0 Then
		      System.DebugLog("ChatView: web-assets/index.html not found or empty")
		      Return
		    End If
		    html = html.ReplaceAll("<!-- CSS_PLACEHOLDER -->", "<style>" + LoadCSSFiles() + "</style>")
		    html = html.ReplaceAll("<!-- JS_PLACEHOLDER -->", "<script>" + LoadJSFiles() + "</script>")
		    Me.LoadHTML(html, baseURL)
		  Catch e As RuntimeException
		    System.DebugLog("ChatView.LoadUI error: " + e.Message)
		    App.AppendDebugLog("ChatView.LoadUI error: " + e.Message)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub RefreshJobs()
		  Var json As String = DBHelper.GetJobsJSON()
		  Me.EvaluateJavaScript("loadJobs(" + json + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub RefreshNotes()
		  Var json As String = DBHelper.GetNotesJSON(App.CurrentProjectPath())
		  Me.EvaluateJavaScript("loadNotes(" + json + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub RefreshSessions()
		  Var json As String = App.GetSessionsJSON()
		  Me.EvaluateJavaScript("loadSessions(" + json + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ClearChat()
		  Me.EvaluateJavaScript("clearChatUI();")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetModeSelect(mode As String)
		  Me.EvaluateJavaScript("document.getElementById('modeSelect').value = " + DBHelper.JSONEscape(mode) + ";")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub LoadBackends(json As String, activeTitle As String)
		  Me.EvaluateJavaScript("loadBackends(" + json + ", " + DBHelper.JSONEscape(activeTitle) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub LoadBackendUI(configJSON As String)
		  Me.EvaluateJavaScript("loadBackendUI(" + configJSON + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetApprovalSelect(value As String)
		  Me.EvaluateJavaScript("setApprovalSelect(" + DBHelper.JSONEscape(value) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ApplyTheme(theme As String)
		  ' Pushes a "system"/"dark"/"light" value into the page. Called at startup
		  ' (so the persisted choice wins over the System default) and whenever the
		  ' user picks a different theme in another window.
		  Me.EvaluateJavaScript("applyTheme(" + DBHelper.JSONEscape(theme) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetBackendStatus(title As String, connected As Boolean, supportsTools As Boolean = True)
		  Me.EvaluateJavaScript("setBackendStatus(" _
		  + DBHelper.JSONEscape(title) + ", " _
		  + If(connected, "true", "false") + ", " _
		  + If(supportsTools, "true", "false") + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetProjectInfo(projectName As String, branch As String)
		  Me.EvaluateJavaScript("setProjectInfo(" _
		  + DBHelper.JSONEscape(projectName) + ", " _
		  + DBHelper.JSONEscape(branch) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowDiff(requestId As String, filePath As String, oldContent As String, newContent As String)
		  Var js As String = "showDiff(" _
		  + DBHelper.JSONEscape(requestId) + ", " _
		  + DBHelper.JSONEscape(filePath) + ", " _
		  + DBHelper.JSONEscape(oldContent) + ", " _
		  + DBHelper.JSONEscape(newContent) + ");"
		  Me.EvaluateJavaScript(js)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowPermissionPrompt(filePath As String, detail As String = "", oldStr As String = "", newStr As String = "")
		  Me.EvaluateJavaScript("showPermissionPrompt(" + DBHelper.JSONEscape(filePath) + "," + DBHelper.JSONEscape(detail) + "," + DBHelper.JSONEscape(oldStr) + "," + DBHelper.JSONEscape(newStr) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowPlanApproval(planText As String)
		  Me.EvaluateJavaScript("showPlanApproval(" + DBHelper.JSONEscape(planText) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowAskUserQuestion(questionsJSON As String)
		  Me.EvaluateJavaScript("showAskUserQuestion(" + questionsJSON + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowToolActivity(toolName As String, detail As String)
		  Me.EvaluateJavaScript("showToolActivity(" _
		  + DBHelper.JSONEscape(toolName) + ", " _
		  + DBHelper.JSONEscape(detail) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowUserMessage(text As String)
		  Me.EvaluateJavaScript("showUserMessage(" + DBHelper.JSONEscape(text) + ");")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function IsReady() As Boolean
		  Return mIsReady
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub EvaluateJavaScript(js As String)
		  Super.EvaluateJavaScript(js)
		End Sub
	#tag EndMethod



	#tag Event
		Function runJavaScriptConfirmPanel(initiatedByFrame As WKFrameInfoMBS, message As String) As Boolean
		  Var d As New MessageDialog
		  d.Icon = MessageDialog.GraphicCaution
		  d.ActionButton.Caption = "OK"
		  d.CancelButton.Visible = True
		  d.Message = message
		  Return d.ShowModal = d.ActionButton
		End Function
	#tag EndEvent

	#tag Property, Flags = &h0
		mIsReady As Boolean
	#tag EndProperty


	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue=""
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue=""
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Width"
			Visible=true
			Group="Position"
			InitialValue="300"
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Height"
			Visible=true
			Group="Position"
			InitialValue="300"
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockLeft"
			Visible=true
			Group="Position"
			InitialValue=""
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockTop"
			Visible=true
			Group="Position"
			InitialValue=""
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockRight"
			Visible=true
			Group="Position"
			InitialValue=""
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockBottom"
			Visible=true
			Group="Position"
			InitialValue=""
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="TabPanelIndex"
			Visible=false
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="TabIndex"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="TabStop"
			Visible=true
			Group="Position"
			InitialValue="True"
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="InitialParent"
			Visible=false
			Group="Position"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Visible"
			Visible=true
			Group="Appearance"
			InitialValue="True"
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Tooltip"
			Visible=true
			Group="Appearance"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
		#tag ViewProperty
			Name="AutoDeactivate"
			Visible=true
			Group="Appearance"
			InitialValue="True"
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Enabled"
			Visible=true
			Group="Appearance"
			InitialValue="True"
			Type="Boolean"
			EditorType="Boolean"
		#tag EndViewProperty
		#tag ViewProperty
			Name="mIsReady"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
