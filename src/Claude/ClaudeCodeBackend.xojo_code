#tag Class
Protected Class ClaudeCodeBackend
Inherits AIBackend
Implements WS.WSClientDelegate
	#tag Method, Flags = &h0
		Sub AnswerUserQuestion(answersJSON As String)
		  If mPendingAskUserQuestionId = "" Then Return
		  mPendingControlToolInput = "{""answers"":" + answersJSON + "}"
		  SendControlResponse(True)
		  mPendingAskUserQuestionId = ""
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ApprovePlan()
		  System.DebugLog("ClaudeCodeBackend: ApprovePlan called, SessionId=" + SessionId + " mMode=" + mMode)
		  mPendingPlanToolUseId = ""
		  mPendingControlRequestId = ""
		  mMode = "ask"
		  Shutdown()
		  Start(mProjectPath)
		  mDelegate.ShowUserMessage("Plan approved. Go ahead and implement it.")
		  mDelegate.SetModeSelect("ask")
		  Var h() As Dictionary
		  SendMessage("Plan approved. Go ahead and implement it.", h)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BuildTool(name As String, description As String, inputSchema As String) As String
		  Return "{""name"":" + DBHelper.JSONEscape(name) _
		  + ",""description"":" + DBHelper.JSONEscape(description) _
		  + ",""inputSchema"":" + inputSchema + "}"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BuildToolsList() As String
		  Return "{""tools"":[" _
		  + BuildTool("getWorkspaceFolders", "Returns workspace folder path", "{}") + "," _
		  + BuildTool("getCurrentSelection", "Returns current editor selection", "{}") + "," _
		  + BuildTool("getLatestSelection",  "Returns last editor selection", "{}") + "," _
		  + BuildTool("getOpenEditors", "Returns open editor list", "{}") + "," _
		  + BuildTool("openFile", "Open a file in the UI", "{""type"":""object"",""properties"":{""filePath"":{""type"":""string""}},""required"":[""filePath""]}") + "," _
		  + BuildTool("openDiff", "Show diff for user review", "{""type"":""object"",""properties"":{""filePath"":{""type"":""string""},""oldContent"":{""type"":""string""},""newContent"":{""type"":""string""}},""required"":[""filePath"",""oldContent"",""newContent""]}") + "," _
		  + BuildTool("saveDocument", "No-op save notification", "{}") + "," _
		  + BuildTool("getDiagnostics", "Returns empty diagnostics", "{}") + "," _
		  + BuildTool("checkDocumentDirty", "Returns false", "{}") + "," _
		  + BuildTool("closeAllDiffTabs", "No-op close diff tabs", "{}") _
		  + "]}"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BuildWSFrame(text As String) As String
		  Var payLen As Integer = text.Bytes
		  Var mb As MemoryBlock
		  If payLen < 126 Then
		    mb = New MemoryBlock(2 + payLen)
		    mb.Byte(0) = &h81
		    mb.Byte(1) = payLen
		    mb.StringValue(2, payLen) = text
		  ElseIf payLen < 65536 Then
		    mb = New MemoryBlock(4 + payLen)
		    mb.Byte(0) = &h81
		    mb.Byte(1) = 126
		    mb.Byte(2) = payLen \ 256
		    mb.Byte(3) = payLen Mod 256
		    mb.StringValue(4, payLen) = text
		  Else
		    mb = New MemoryBlock(10 + payLen)
		    mb.Byte(0) = &h81
		    mb.Byte(1) = 127
		    mb.Byte(2) = 0
		    mb.Byte(3) = 0
		    mb.Byte(4) = 0
		    mb.Byte(5) = 0
		    mb.Byte(6) = (payLen \ &h1000000) Mod 256
		    mb.Byte(7) = (payLen \ &h10000) Mod 256
		    mb.Byte(8) = (payLen \ &h100) Mod 256
		    mb.Byte(9) = payLen Mod 256
		    mb.StringValue(10, payLen) = text
		  End If
		  Return mb.StringValue(0, mb.Size)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Constructor()
		  Title = "Claude Code"
		  SupportsTools = True
		  IsConnected = False
		  SupportsPlanMode = True
		  SupportsPermissionPrompts = True
		  SupportsImageInput = True
		  SupportsReasoningEffort = True
		  Models.Add("claude-opus-4-7")
		  Models.Add("claude-sonnet-4-6")
		  Models.Add("claude-haiku-4-5")
		  DefaultModel = "claude-sonnet-4-6"
		  mPendingDiffs = New Dictionary
		  mModel = "claude-sonnet-4-6"
		  mMode = "ask"
		  mEffort = "medium"
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function DecodeWSFrame(buffer As String) As String
		  If buffer.Bytes < 2 Then Return ""
		  
		  Var buf As New MemoryBlock(buffer.Bytes)
		  buf.StringValue(0, buffer.Bytes) = buffer
		  
		  Var b1 As Integer = buf.Byte(1)
		  Var masked As Boolean = (b1 And &h80) <> 0
		  Var payLen As Integer = b1 And &h7F
		  
		  Var headerLen As Integer = 2
		  If payLen = 126 Then
		    If buffer.Bytes < 4 Then Return ""
		    payLen = buf.Byte(2) * 256 + buf.Byte(3)
		    headerLen = 4
		  ElseIf payLen = 127 Then
		    If buffer.Bytes < 10 Then Return ""
		    payLen = buf.Byte(6) * &h1000000 + buf.Byte(7) * &h10000 + buf.Byte(8) * &h100 + buf.Byte(9)
		    headerLen = 10
		  End If
		  
		  Var maskLen As Integer = If(masked, 4, 0)
		  Var totalLen As Integer = headerLen + maskLen + payLen
		  If buffer.Bytes < totalLen Then Return ""
		  
		  Var out As New MemoryBlock(payLen)
		  Var i As Integer
		  If masked Then
		    Var m0 As Integer = buf.Byte(headerLen)
		    Var m1 As Integer = buf.Byte(headerLen + 1)
		    Var m2 As Integer = buf.Byte(headerLen + 2)
		    Var m3 As Integer = buf.Byte(headerLen + 3)
		    For i = 0 To payLen - 1
		      Var rawByte As Integer = buf.Byte(headerLen + 4 + i)
		      Select Case i Mod 4
		      Case 0
		        out.Byte(i) = rawByte Xor m0
		      Case 1
		        out.Byte(i) = rawByte Xor m1
		      Case 2
		        out.Byte(i) = rawByte Xor m2
		      Case 3
		        out.Byte(i) = rawByte Xor m3
		      End Select
		    Next
		  Else
		    For i = 0 To payLen - 1
		      out.Byte(i) = buf.Byte(headerLen + i)
		    Next
		  End If
		  
		  mWSBuffer = buffer.Middle(totalLen)
		  Return out.StringValue(0, payLen)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub DeleteLockFile()
		  If mLockFile <> Nil And mLockFile.Exists Then
		    mLockFile.Delete
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function DoWebSocketHandshake(sock As WS.WSClientSocket, request As String) As Boolean
		  Var authHeader As String = ExtractHTTPHeader(request, "x-claude-code-ide-authorization")
		  If authHeader <> mAuthToken Then
		    sock.Write "HTTP/1.1 401 Unauthorized" + Chr(13) + Chr(10) + Chr(13) + Chr(10)
		    sock.Close
		    Return False
		  End If
		  
		  Var wsKey As String = ExtractHTTPHeader(request, "Sec-WebSocket-Key")
		  If wsKey = "" Then Return False
		  
		  Var magic As String = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
		  Var sha1 As String = SHA1Base64(wsKey + magic)
		  
		  Var response As String = "HTTP/1.1 101 Switching Protocols" + Chr(13) + Chr(10) _
		  + "Upgrade: websocket" + Chr(13) + Chr(10) _
		  + "Connection: Upgrade" + Chr(13) + Chr(10) _
		  + "Sec-WebSocket-Accept: " + sha1 + Chr(13) + Chr(10) _
		  + Chr(13) + Chr(10)
		  sock.Write response
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ExtractHTTPHeader(request As String, headerName As String) As String
		  Var lines() As String = request.Split(Chr(10))
		  Var search As String = headerName.Lowercase + ": "
		  For Each line As String In lines
		    If line.Lowercase.Left(search.Length) = search Then
		      Return line.Middle(search.Length).Trim
		    End If
		  Next
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindFreePort(startPort As Integer, endPort As Integer) As Integer
		  Var p As Integer = startPort
		  While p <= endPort
		    Try
		      Var srv As New ServerSocket
		      srv.Port = p
		      srv.Listen
		      If srv.IsListening Then
		        srv.StopListening
		        Return p
		      End If
		      srv.StopListening
		    Catch e As RuntimeException
		    End Try
		    p = p + 1
		  Wend
		  Return 0
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function GenerateUUID() As String
		  Var sh As New Shell
		  sh.Execute("uuidgen")
		  Var result As String = sh.Result.Trim
		  If result <> "" Then Return result
		  Var r As New Random
		  Return Hex(r.InRange(0, &hFFFFFF)) + "-" + Hex(r.InRange(0, &hFFFF)) _
		  + "-" + Hex(r.InRange(0, &hFFFF)) + "-" + Hex(r.InRange(0, &hFFFFFFFF))
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionChatJSON(uuid As String) As String
		  If mProjectPath = "" Or uuid = "" Then Return "[]"
		  Var claudeProjects As FolderItem = SpecialFolder.UserHome.Child(".claude").Child("projects")

		  Var slugCandidates() As String
		  slugCandidates.Add(mProjectPath.ReplaceAll("/", "-"))
		  Var projectFolder As FolderItem = New FolderItem(mProjectPath, FolderItem.PathModes.Native)
		  If projectFolder.Parent <> Nil Then
		    slugCandidates.Add(projectFolder.Parent.NativePath.ReplaceAll("/", "-"))
		  End If

		  Var f As FolderItem
		  For Each slug As String In slugCandidates
		    Var dir As FolderItem = claudeProjects.Child(slug)
		    If dir = Nil Or Not dir.Exists Then Continue
		    Var candidate As New FolderItem(dir.NativePath + "/" + uuid + ".jsonl", FolderItem.PathModes.Native)
		    If candidate <> Nil And candidate.Exists Then
		      f = candidate
		      Exit
		    End If
		  Next
		  If f = Nil Then Return "[]"

		  Var allText As String
		  Try
		    Var ts As TextInputStream = TextInputStream.Open(f)
		    ts.Encoding = Encodings.UTF8
		    allText = ts.ReadAll
		    ts.Close
		  Catch ioe As IOException
		    System.DebugLog("GetSessionChatJSON: cannot read " + uuid + " — " + ioe.Message)
		    Return "[]"
		  End Try

		  Var lines() As String = allText.Split(Chr(10))
		  Var output As New JSONItem("[]")
		  output.Compact = True
		  Var kept As Integer = 0

		  For Each line As String In lines
		    line = line.Trim
		    If line = "" Then Continue
		    App.DoEvents
		    If mDelegate <> Nil Then
		      Var pct As Integer = If(lines.Count > 0, (kept * 100) \ lines.Count, 0)
		      mDelegate.EvaluateJavaScript("updateSessionProgress(" + pct.ToString + ");")
		    End If

		    Var item As JSONItem
		    Try
		      item = New JSONItem(line)
		    Catch e As JSONException
		      Continue
		    End Try

		    If Not item.HasName("message") Then Continue
		    Var msg As JSONItem = AsJSONItem(item.Value("message"))
		    If msg = Nil Then Continue

		    Var role As String = msg.Lookup("role", "")
		    If role <> "user" And role <> "assistant" Then Continue
		    If Not msg.HasName("content") Then Continue

		    Var contentItem As JSONItem = AsJSONItem(msg.Value("content"))
		    Var text As String = ""

		    If contentItem = Nil Or Not contentItem.IsArray Then
		      text = msg.Lookup("content", "")
		      If text.Trim.Left(1) = "<" Then Continue
		    Else
		      Var hasToolResult As Boolean = False
		      For i As Integer = 0 To contentItem.Count - 1
		        Var blk As JSONItem = AsJSONItem(contentItem.ChildAt(i))
		        If blk <> Nil And blk.Lookup("type", "") = "tool_result" Then
		          hasToolResult = True
		          Exit
		        End If
		      Next
		      If hasToolResult Then Continue
		      For i As Integer = 0 To contentItem.Count - 1
		        Var block As JSONItem = AsJSONItem(contentItem.ChildAt(i))
		        If block = Nil Or block.Lookup("type", "") <> "text" Then Continue
		        Var piece As String = block.Lookup("text", "")
		        piece = piece.Trim
		        If piece <> "" Then
		          If text <> "" Then text = text + Chr(10)
		          text = text + piece
		        End If
		      Next
		    End If

		    text = text.Trim
		    If text = "" Then Continue

		    Var entry As New JSONItem
		    entry.Value("role") = role
		    entry.Value("content") = text
		    output.Add(entry)
		    kept = kept + 1
		  Next

		  Return output.ToString
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionsJSON() As String
		  Return App.GetSessionsJSON()
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HandleAssistantMessage(root As JSONItem)
		  Var msg As JSONItem
		  If root.HasName("message") Then
		    msg = root.Value("message")
		  Else
		    msg = root
		  End If
		  If Not msg.HasName("content") Then Return
		  
		  Var content As JSONItem = msg.Value("content")
		  If Not content.IsArray Then Return
		  
		  Var sawToolUse As Boolean = False
		  Var toolNameForActivity As String = ""
		  
		  Var n As Integer = content.LastRowIndex
		  For i As Integer = 0 To n
		    Var block As JSONItem = content.ChildAt(i)
		    Var blockType As String = block.Lookup("type", "")
		    
		    If blockType = "text" Then
		      Var token As String = block.Lookup("text", "")
		      If token <> "" Then FireOnToken(token)
		      
		    ElseIf blockType = "tool_use" Then
		      sawToolUse = True
		      Var toolName As String = block.Lookup("name", "")
		      If toolName = "ExitPlanMode" Then
		        mPendingPlanToolUseId = block.Lookup("id", "")
		      ElseIf toolName <> "" And toolName <> "EnterPlanMode" Then
		        toolNameForActivity = toolName
		      End If
		    End If
		  Next
		  
		  If sawToolUse And toolNameForActivity <> "" Then
		    mDelegate.ShowToolActivity(toolNameForActivity, "")
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h5
		Protected Sub HandleLine(json As String)
		  System.DebugLog("Claude stdout: " + json.Left(200))
		  
		  Var root As JSONItem = ParseJSONOrNil(json)
		  If root = Nil Then Return
		  
		  Var msgType As String = root.Lookup("type", "")
		  
		  Select Case msgType
		    
		  Case "system"
		    Var subtype As String = root.Lookup("subtype", "")
		    If subtype = "init" Then
		      IsConnected = True
		      SessionId = root.Lookup("session_id", "")
		      mDelegate.SetBackendStatus(Title, True, SupportsTools)
		      System.DebugLog("ClaudeCodeBackend: claude connected, session=" + SessionId)
		      mDelegate.RefreshSessions()
		    ElseIf subtype = "task_started" Or subtype = "task_progress" Then
		      Var desc As String = root.Lookup("description", "")
		      If desc <> "" Then mDelegate.ShowToolActivity("task", desc)
		    End If
		    
		  Case "stream_event"
		    If root.HasName("event") Then
		      Var seEvent As JSONItem = root.Value("event")
		      Var seType As String = seEvent.Lookup("type", "")
		      If seType = "content_block_delta" And seEvent.HasName("delta") Then
		        Var delta As JSONItem = seEvent.Value("delta")
		        Var deltaType As String = delta.Lookup("type", "")
		        If deltaType = "text_delta" Then
		          Var token As String = delta.Lookup("text", "")
		          If token <> "" Then
		            mStreamedText = True
		            FireOnToken(token)
		          End If
		        ElseIf deltaType = "input_json_delta" Then
		          mActiveToolInputJSON = mActiveToolInputJSON + delta.Lookup("partial_json", "")
		        End If
		      ElseIf seType = "content_block_start" And seEvent.HasName("content_block") Then
		        Var cb As JSONItem = seEvent.Value("content_block")
		        Var cbName As String = cb.Lookup("name", "")
		        Var cbType As String = cb.Lookup("type", "")
		        If cbType = "thinking" Then
		          mDelegate.ShowThinkingIndicator("Thinking…")
		        ElseIf cbName = "ExitPlanMode" Then
		          Var isTopLevel As Boolean = True
		          If root.HasName("parent_tool_use_id") Then
		            Var pVal As Variant = root.Value("parent_tool_use_id")
		            If Not pVal.IsNull Then isTopLevel = False
		          End If
		          If isTopLevel Then
		            mPendingPlanToolUseId = cb.Lookup("id", "")
		            System.DebugLog("ClaudeCodeBackend: ExitPlanMode detected in stream, tool_use_id=" + mPendingPlanToolUseId)
		            Var planText As String = ReadLatestPlanFile()
		            mDelegate.ShowPlanApproval(planText)
		          Else
		            System.DebugLog("ClaudeCodeBackend: ExitPlanMode ignored — inside subagent")
		          End If
		        ElseIf cb.Lookup("type", "") = "tool_use" And cbName <> "" And cbName <> "EnterPlanMode" Then
		          mActiveToolName = cbName
		          mActiveToolInputJSON = ""
		          mDelegate.ShowToolActivity(cbName, "")
		        End If
		      ElseIf seType = "content_block_stop" Then
		        If mActiveToolName <> "" Then
		          If mActiveToolInputJSON <> "" Then
		            Var detail As String = ExtractToolDetail(mActiveToolName, mActiveToolInputJSON)
		            If detail <> "" Then mDelegate.ShowToolActivity(mActiveToolName, detail)
		          End If
		          // Keep activity visible — tool is now running; cleared on next token
		          mActiveToolInputJSON = ""
		        End If
		      End If
		    End If
		    
		  Case "assistant"
		    If Not mStreamedText Then HandleAssistantMessage(root)

		  Case "result"
		    mStreamedText = False
		    mActiveToolName = ""
		    mActiveToolInputJSON = ""
		    FireOnDone()
		    If root.Lookup("subtype", "") = "error" Then
		      FireOnError(root.Lookup("result", ""))
		    End If
		    
		  Case "user"
		    Var permPrefix As String = "Claude requested permissions to write to "
		    Var permSuffix As String = ", but you haven't granted it yet."
		    Var pidx As Integer = json.IndexOf(permPrefix)
		    If pidx >= 0 Then
		      pidx = pidx + permPrefix.Length
		      Var endIdx As Integer = json.IndexOf(pidx, permSuffix)
		      If endIdx > pidx Then
		        Var filePath As String = json.Middle(pidx, endIdx - pidx)
		        mDelegate.ShowPermissionPrompt(filePath)
		      End If
		    End If
		    
		  Case "control_request"
		    Var reqWrap As JSONItem = root
		    If root.HasName("request") Then
		      Var rw As JSONItem = root.Value("request")
		      If rw <> Nil Then reqWrap = rw
		    End If
		    Var subtype As String = reqWrap.Lookup("subtype", "")
		    If subtype = "" Then subtype = root.Lookup("subtype", "")
		    System.DebugLog("control_request subtype=" + subtype + " json=" + json.Left(400))
		    If subtype = "can_use_tool" Then
		      mPendingControlRequestId = root.Lookup("request_id", "")
		      If mPendingControlRequestId = "" Then mPendingControlRequestId = reqWrap.Lookup("request_id", "")
		      mPendingControlToolUseId = reqWrap.Lookup("tool_use_id", "")
		      If mPendingControlToolUseId = "" Then mPendingControlToolUseId = root.Lookup("tool_use_id", "")
		      Var inputHost As JSONItem = reqWrap
		      If Not inputHost.HasName("input") And root.HasName("input") Then inputHost = root
		      If inputHost.HasName("input") Then
		        Var inputItem As JSONItem = inputHost.Value("input")
		        inputItem.Compact = True
		        mPendingControlToolInput = inputItem.ToString
		      Else
		        mPendingControlToolInput = "{}"
		      End If
		      System.DebugLog("control_request captured: request_id=" + mPendingControlRequestId _
		      + " tool_use_id=" + mPendingControlToolUseId _
		      + " input=" + mPendingControlToolInput.Left(200) _
		      + " autoApprove=" + mAutoApprove.ToString)
		      Var toolName As String = reqWrap.Lookup("tool_name", "")
		      If toolName = "" Then toolName = root.Lookup("tool_name", "")
		      If toolName = "AskUserQuestion" Then
		        Var qJSON As String = "[]"
		        If inputHost.HasName("input") Then
		          Var inputItem As JSONItem = inputHost.Value("input")
		          If inputItem.HasName("questions") Then
		            Var qArr As JSONItem = inputItem.Value("questions")
		            qArr.Compact = True
		            qJSON = qArr.ToString
		          End If
		        End If
		        mPendingAskUserQuestionId = mPendingControlRequestId
		        mDelegate.ShowAskUserQuestion(qJSON)
		      ElseIf mAutoApprove Then
		        System.DebugLog("ClaudeCodeBackend: auto-approving control_request (mAutoApprove=true)")
		        SendControlResponse(True)
		      Else
		        Var filePath As String = ""
		        Var cmdDetail As String = ""
		        If inputHost.HasName("input") Then
		          Var inputItem As JSONItem = inputHost.Value("input")
		          filePath = inputItem.Lookup("file_path", "")
		          If filePath = "" Then filePath = inputItem.Lookup("path", "")
		          If filePath = "" Then
		            Var cmdStr As String = inputItem.Lookup("command", "")
		            If cmdStr <> "" Then cmdDetail = cmdStr
		          End If
		        End If
		        If filePath = "" And cmdDetail = "" Then filePath = toolName
		        mDelegate.ShowPermissionPrompt(filePath, cmdDetail)
		      End If
		    ElseIf subtype = "exit_plan_mode" Or subtype = "plan_mode_end" Then
		      System.DebugLog("ClaudeCodeBackend: exit_plan_mode control_request ignored (handled via stream_event)")
		    End If
		    
		  Case "rate_limit_event"
		    Var rlInfo As JSONItem = root.Lookup("rate_limit_info", Nil)
		    If rlInfo <> Nil And rlInfo.Lookup("status", "") = "rejected" Then
		      Var usingOverage As Boolean = rlInfo.Lookup("isUsingOverage", False)
		      If Not usingOverage Then
		        Var resetsAt As Int64 = rlInfo.Lookup("resetsAt", 0)
		        Var waitMsg As String = "Rate limit reached — waiting for reset"
		        If resetsAt > 0 Then
		          Var d As New Date(1970, 1, 1, 0, 0, 0)
		          d.TotalSeconds = d.TotalSeconds + resetsAt
		          waitMsg = "Rate limit reached — resets at " + Format(d.Hour, "00") + ":" + Format(d.Minute, "00")
		        End If
		        mDelegate.ShowToolActivity("rate_limit", waitMsg)
		      End If
		    End If
		    
		  End Select
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HandleToolCall(id As String, toolName As String, args As JSONItem)
		  Select Case toolName
		    
		  Case "getWorkspaceFolders"
		    SendMCPToolResult(id, "{""workspaceFolders"":[" + DBHelper.JSONEscape(mProjectPath) + "]}")
		    
		  Case "getCurrentSelection", "getLatestSelection"
		    SendMCPToolResult(id, "{""text"":" + DBHelper.JSONEscape(mLastSelection) + ",""filePath"":""""}")
		    
		  Case "getOpenEditors"
		    SendMCPToolResult(id, "{""editors"":[]}")
		    
		  Case "openFile"
		    Var filePath As String = args.Lookup("filePath", "")
		    mDelegate.ShowToolActivity("openFile", filePath)
		    SendMCPToolResult(id, "{""success"":true}")
		    
		  Case "openDiff"
		    Var filePath As String = args.Lookup("filePath", "")
		    Var oldContent As String = args.Lookup("oldContent", "")
		    Var newContent As String = args.Lookup("newContent", "")
		    Var reqId As String = "diff-" + id
		    mPendingDiffs.Value(reqId) = id
		    mDelegate.ShowToolActivity("openDiff", filePath)
		    mDelegate.ShowDiff(reqId, filePath, oldContent, newContent)
		    
		  Case "saveDocument"
		    SendMCPToolResult(id, "{""success"":true}")
		    
		  Case "getDiagnostics"
		    SendMCPToolResult(id, "{""diagnostics"":[]}")
		    
		  Case "checkDocumentDirty"
		    SendMCPToolResult(id, "{""isDirty"":false}")
		    
		  Case "closeAllDiffTabs"
		    SendMCPToolResult(id, "{""success"":true}")
		    
		  Case "AskUserQuestion"
		    mPendingAskUserQuestionId = id
		    Var qJSON As String = "[]"
		    If args.HasName("questions") Then
		      Var qArr As JSONItem = args.Value("questions")
		      qArr.Compact = True
		      qJSON = qArr.ToString
		    End If
		    mDelegate.ShowAskUserQuestion(qJSON)
		    
		  Case "EnterPlanMode"
		    SendMCPToolResult(id, "{""success"":true}")
		    
		  Case "ExitPlanMode"
		    SendMCPToolResult(id, "{""success"":true}")
		    
		  Else
		    SendMCPError(id, -32601, "Method not found: " + toolName)
		    
		  End Select
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HandleWSMessage(json As String)
		  System.DebugLog("WS message from claude: " + json.Left(200))
		  Var root As JSONItem = ParseJSONOrNil(json)
		  If root = Nil Then
		    System.DebugLog("HandleWSMessage: malformed JSON")
		    Return
		  End If
		  
		  Var method As String = root.Lookup("method", "")
		  Var id As String = JSONIdAsLiteral(root)
		  
		  Select Case method
		    
		  Case "initialize"
		    SendMCPResult(id, "{""protocolVersion"":""2024-11-05""" _
		    + ",""capabilities"":{""tools"":{}}" _
		    + ",""serverInfo"":{""name"":""XMCPStudio"",""version"":""1.0""}}")
		    
		  Case "tools/list"
		    SendMCPResult(id, BuildToolsList())
		    
		  Case "tools/call"
		    If Not root.HasName("params") Then Return
		    Var params As JSONItem = root.Value("params")
		    Var toolName As String = params.Lookup("name", "")
		    Var toolArgs As JSONItem
		    If params.HasName("arguments") Then
		      toolArgs = params.Value("arguments")
		    Else
		      toolArgs = New JSONItem("{}")
		    End If
		    HandleToolCall(id, toolName, toolArgs)
		    
		  End Select
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function JSONIdAsLiteral(root As JSONItem) As String
		  If Not root.HasName("id") Then Return ""
		  Var v As Variant = root.Value("id")
		  If v.Type = Variant.TypeString Then
		    Return DBHelper.JSONEscape(v.StringValue)
		  End If
		  Return v.StringValue
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub LaunchClaude()
		  Var claudePath As String = ResolveClaudePath()
		  If claudePath = "" Then
		    System.DebugLog("ClaudeCodeBackend: claude CLI not found in ~/.local/bin, ~/.claude/local, /opt/homebrew/bin, /usr/local/bin, or PATH")
		    Var dlg As New MessageDialog
		    dlg.Message = "Claude Code CLI not found"
		    dlg.Explanation = "The Claude Code CLI does not appear to be installed on this machine." + EndOfLine + EndOfLine + "Visit Anthropic's support pages or search for 'Claude Code install' for up-to-date installation instructions."
		    dlg.ActionButton.Caption = "OK"
		    Call dlg.ShowModal
		    Return
		  End If
		  System.DebugLog("ClaudeCodeBackend: using claude at " + claudePath)
		  
		  Var args() As String
		  args.Add("--output-format")
		  args.Add("stream-json")
		  args.Add("--input-format")
		  args.Add("stream-json")
		  args.Add("--verbose")
		  args.Add("--ide")
		  args.Add("--thinking")
		  args.Add("disabled")
		  args.Add("--include-partial-messages")
		  If mModel <> "" Then
		    args.Add("--model")
		    args.Add(mModel)
		  End If
		  If mEffort <> "" And mEffort <> "medium" Then
		    args.Add("--effort")
		    args.Add(mEffort)
		  End If
		  Select Case mMode
		  Case "auto", ""
		    args.Add("--dangerously-skip-permissions")
		  Case "ask", "default"
		    args.Add("--permission-prompt-tool")
		    args.Add("stdio")
		  Case "plan"
		    args.Add("--permission-mode")
		    args.Add("plan")
		  End Select
		  If SessionId <> "" Then
		    args.Add("--resume")
		    args.Add(SessionId)
		  End If

		  StartSubprocess(claudePath, args)
		  
		  System.DebugLog("ClaudeCodeBackend: claude launched via NSTaskMBS, PID=" + mTask.processIdentifier.ToString + " mMode=" + mMode + " mStdinFD=" + mStdinFD.ToString)
		  IsConnected = True
		  If mDelegate.IsReady Then
		    mDelegate.SetBackendStatus(Title, True, SupportsTools)
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub NewSession()
		  SessionId = ""
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OnClientData(sock As WS.WSClientSocket, data As String)
		  System.DebugLog("ClaudeCodeBackend: WS data received, len=" + data.Length.ToString + " handshakeDone=" + mHandshakeDone.ToString)
		  If mClientSocket = Nil Then mClientSocket = sock
		  If Not mHandshakeDone Then
		    If DoWebSocketHandshake(sock, data) Then
		      mHandshakeDone = True
		      System.DebugLog("ClaudeCodeBackend: WS handshake complete")
		    Else
		      System.DebugLog("ClaudeCodeBackend: WS handshake FAILED, data=" + data.Left(200))
		    End If
		    Return
		  End If
		  
		  mWSBuffer = mWSBuffer + data
		  Var msg As String = DecodeWSFrame(mWSBuffer)
		  While msg <> ""
		    HandleWSMessage(msg)
		    msg = DecodeWSFrame(mWSBuffer)
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OnClientError(sock As WS.WSClientSocket, err As RuntimeException)
		  #Pragma Unused sock
		  #Pragma Unused err
		  mHandshakeDone = False
		  mWSBuffer = ""
		  mClientSocket = Nil
		  System.DebugLog("ClaudeCodeBackend: WS client disconnected")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OnDiffAccepted(requestId As String, filePath As String)
		  If mPendingDiffs.HasKey(requestId) Then
		    Var semId As String = mPendingDiffs.Value(requestId)
		    mPendingDiffs.Remove(requestId)
		    SendMCPResult(semId, "{""accepted"":true,""filePath"":" + DBHelper.JSONEscape(filePath) + "}")
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OnDiffRejected(requestId As String)
		  If mPendingDiffs.HasKey(requestId) Then
		    Var semId As String = mPendingDiffs.Value(requestId)
		    mPendingDiffs.Remove(requestId)
		    SendMCPResult(semId, "{""accepted"":false}")
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ReadLatestPlanFile() As String
		  Var plansDir As FolderItem = SpecialFolder.UserHome.Child(".claude").Child("plans")
		  If plansDir = Nil Or Not plansDir.Exists Then Return ""
		  Var newest As FolderItem
		  Var newestTime As Double = 0
		  Var count As Integer = plansDir.Count
		  Var i As Integer
		  For i = 1 To count
		    Var f As FolderItem = plansDir.ChildAt(i - 1)
		    If f = Nil Or f.IsFolder Then Continue
		    If Not f.Name.EndsWith(".md") Then Continue
		    Var modTime As Double = f.ModificationDate.TotalSeconds
		    If modTime > newestTime Then
		      newestTime = modTime
		      newest = f
		    End If
		  Next
		  If newest = Nil Then Return ""
		  Try
		    Var ts As TextInputStream = TextInputStream.Open(newest)
		    ts.Encoding = Encodings.UTF8
		    Var result As String = ts.ReadAll
		    ts.Close
		    System.DebugLog("ClaudeCodeBackend: read plan file: " + newest.Name)
		    Return result
		  Catch e As IOException
		    System.DebugLog("ClaudeCodeBackend.ReadLatestPlanFile: " + e.Message)
		    Return ""
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub RejectPlan()
		  System.DebugLog("ClaudeCodeBackend: RejectPlan called, SessionId=" + SessionId + " mMode=" + mMode)
		  mPendingPlanToolUseId = ""
		  mPendingControlRequestId = ""
		  Shutdown()
		  Start(mProjectPath)
		  mDelegate.ShowUserMessage("Plan rejected. Please revise it.")
		  Var h() As Dictionary
		  SendMessage("Plan rejected. Please revise it.", h)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ResolveClaudePath() As String
		  Var candidates() As String
		  candidates.Add(SpecialFolder.UserHome.NativePath + "/.local/bin/claude")
		  candidates.Add(SpecialFolder.UserHome.NativePath + "/.claude/local/claude")
		  candidates.Add("/opt/homebrew/bin/claude")
		  candidates.Add("/usr/local/bin/claude")
		  For Each p As String In candidates
		    Var fc As New FolderItem(p, FolderItem.PathModes.Native)
		    If fc <> Nil And fc.Exists Then Return p
		  Next
		  Var sh As New Shell
		  sh.Execute("/bin/zsh -lc 'command -v claude' 2>/dev/null")
		  Var found As String = sh.Result.Trim
		  If found <> "" Then Return found
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ResumeSession(uuid As String)
		  SessionId = uuid
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendControlResponse(allow As Boolean)
		  If mPendingControlRequestId = "" Then
		    System.DebugLog("SendControlResponse: no pending request_id, dropping " + If(allow, "allow", "deny"))
		    Return
		  End If
		  Var safeInput As String = mPendingControlToolInput.Trim
		  If safeInput = "" Or safeInput.Left(1) <> "{" Or safeInput.Right(1) <> "}" Then
		    safeInput = "{}"
		  End If
		  System.DebugLog("SendControlResponse: " + If(allow, "ALLOW", "DENY") _
		  + " request_id=" + mPendingControlRequestId _
		  + " tool_use_id=" + mPendingControlToolUseId _
		  + " updatedInput=" + safeInput.Left(200))
		  Var response As String
		  If allow Then
		    response = "{""type"":""control_response"",""response"":{""subtype"":""success""," _
		    + """request_id"":" + DBHelper.JSONEscape(mPendingControlRequestId) + "," _
		    + """response"":{""behavior"":""allow""," _
		    + """updatedInput"":" + safeInput + "," _
		    + """toolUseID"":" + DBHelper.JSONEscape(mPendingControlToolUseId) + "}}}" + Chr(10)
		  Else
		    response = "{""type"":""control_response"",""response"":{""subtype"":""success""," _
		    + """request_id"":" + DBHelper.JSONEscape(mPendingControlRequestId) + "," _
		    + """response"":{""behavior"":""deny""," _
		    + """message"":""Permission denied by user""," _
		    + """toolUseID"":" + DBHelper.JSONEscape(mPendingControlToolUseId) + "}}}" + Chr(10)
		  End If
		  mPendingControlRequestId = ""
		  mPendingControlToolInput = ""
		  mPendingControlToolUseId = ""
		  WriteToStdin(response)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendMCPError(id As String, code As Integer, message As String)
		  Var msg As String = "{""jsonrpc"":""2.0"",""id"":" + id _
		  + ",""error"":{""code"":" + code.ToString _
		  + ",""message"":" + DBHelper.JSONEscape(message) + "}}"
		  SendToWSClient(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendMCPResult(id As String, resultJSON As String)
		  Var msg As String = "{""jsonrpc"":""2.0"",""id"":" + id + ",""result"":" + resultJSON + "}"
		  SendToWSClient(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendMCPToolError(id As String, errorText As String)
		  Var msg As String = "{""jsonrpc"":""2.0"",""id"":" + id _
		  + ",""result"":{""content"":[{""type"":""text"",""text"":" _
		  + DBHelper.JSONEscape(errorText) + "}],""isError"":true}}"
		  SendToWSClient(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendMCPToolResult(id As String, contentJSON As String)
		  Var msg As String = "{""jsonrpc"":""2.0"",""id"":" + id _
		  + ",""result"":{""content"":[{""type"":""text"",""text"":" _
		  + DBHelper.JSONEscape(contentJSON) + "}]}}"
		  SendToWSClient(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendMessage(text As String, history() As Dictionary)
		  #Pragma Unused history
		  If mStdinFD < 0 Then
		    FireOnError("Claude Code not running.")
		    Return
		  End If
		  Var msg As String = "{""type"":""user"",""message"":{""role"":""user"",""content"":" + DBHelper.JSONEscape(text) + "}}" + Chr(10)
		  System.DebugLog("ClaudeCodeBackend: SendMessage bytes=" + msg.Bytes.ToString + " text=" + text.Left(80))
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendMessageWithImage(text As String, imageBase64 As String, imageMediaType As String, history() As Dictionary)
		  #Pragma Unused history
		  If mStdinFD < 0 Then
		    FireOnError("Claude Code not running.")
		    Return
		  End If
		  Var contentArr As String
		  contentArr = "["
		  If text <> "" Then
		    contentArr = contentArr + "{""type"":""text"",""text"":" + DBHelper.JSONEscape(text) + "},"
		  End If
		  contentArr = contentArr + "{""type"":""image"",""source"":{""type"":""base64"",""media_type"":" + DBHelper.JSONEscape(imageMediaType) + ",""data"":" + DBHelper.JSONEscape(imageBase64) + "}}"
		  contentArr = contentArr + "]"
		  Var msg As String = "{""type"":""user"",""message"":{""role"":""user"",""content"":" + contentArr + "}}" + Chr(10)
		  System.DebugLog("ClaudeCodeBackend: SendMessageWithImage bytes=" + msg.Bytes.ToString + " text=" + text.Left(60))
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendToWSClient(json As String)
		  If mClientSocket = Nil Or Not mHandshakeDone Then Return
		  Var frame As String = BuildWSFrame(json)
		  mClientSocket.Write frame
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetAutoApprove(value As Boolean)
		  mAutoApprove = value
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetMode(m As String)
		  System.DebugLog("ClaudeCodeBackend: SetMode called, m=" + m)
		  mMode = m
		  SessionId = ""
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetModel(m As String)
		  mModel = m
		  SessionId = ""
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetReasoningEffort(effort As String)
		  mEffort = effort
		  SessionId = ""
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function SHA1Base64(input As String) As String
		  Var hash As String = Crypto.SHA1(input)
		  Return EncodeBase64(hash, 0)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Shutdown()
		  ShutdownSubprocess()
		  DeleteLockFile()
		  StopWSServer()
		  IsConnected = False
		  mPort = 0
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Start(projectPath As String)
		  System.DebugLog("ClaudeCodeBackend: Start called, mMode=" + mMode + " SessionId=" + SessionId)
		  mProjectPath = projectPath
		  mAutoApprove = False
		  If mAuthToken = "" Then mAuthToken = GenerateUUID()
		  
		  mPort = FindFreePort(10000, 10999)
		  If mPort = 0 Then
		    FireOnError("No free port available in range 10000-10999")
		    Return
		  End If
		  
		  StartWSServer()
		  WriteLockFile()
		  LaunchClaude()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub StartWSServer()
		  mServerSocket = New WS.WSServerSocket
		  mServerSocket.SetDelegate(Me)
		  mServerSocket.Port = mPort
		  mServerSocket.MaximumSocketsConnected = 1
		  mServerSocket.MinimumSocketsAvailable = 1
		  mServerSocket.Listen
		  System.DebugLog("ClaudeCodeBackend: WS listening on port " + mPort.ToString)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub StopGeneration()
		  Shutdown()
		  FireOnDone()
		  If mProjectPath <> "" Then Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub StopWSServer()
		  If mServerSocket <> Nil Then
		    mServerSocket.StopListening
		    mServerSocket = Nil
		  End If
		  mClientSocket = Nil
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub WriteLockFile()
		  Var homeDir As FolderItem = SpecialFolder.UserHome
		  Var claudeDir As FolderItem = homeDir.Child(".claude").Child("ide")
		  If Not claudeDir.Exists Then claudeDir.CreateFolder
		  
		  mLockFile = claudeDir.Child(mPort.ToString + ".lock")
		  
		  Declare Function getpid Lib "libc.dylib" () As Integer
		  Var pid As Integer = getpid()
		  
		  Var json As String = "{" _
		  + """pid"":" + pid.ToString + "," _
		  + """workspaceFolders"":[" + DBHelper.JSONEscape(mProjectPath) + "]," _
		  + """ideName"":""XMCPStudio""," _
		  + """transport"":""ws""," _
		  + """authToken"":" + DBHelper.JSONEscape(mAuthToken) _
		  + "}"
		  
		  Try
		    Var ts As TextOutputStream = TextOutputStream.Create(mLockFile)
		    ts.Write json
		    ts.Close
		    System.DebugLog("ClaudeCodeBackend: lock file written: " + mLockFile.NativePath)
		  Catch e As IOException
		    System.DebugLog("ClaudeCodeBackend: lock file write FAILED: " + e.Message)
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ExtractToolDetail(toolName As String, inputJSON As String) As String
		  Var j As JSONItem
		  Try
		    j = New JSONItem(inputJSON)
		  Catch
		    Return ""
		  End Try
		  
		  Select Case toolName
		  Case "str_replace_based_edit_tool", "create_file", "write_file", "view_file", "read_file", "delete_file"
		    Var p As String = j.Lookup("path", "")
		    If p = "" Then p = j.Lookup("file_path", "")
		    Return If(p <> "", LastPathComponent(p), "")
		  Case "Bash", "bash", "shell", "computer"
		    Var cmd As String = j.Lookup("command", "")
		    If cmd = "" Then cmd = j.Lookup("input", "")
		    If cmd.Length > 60 Then cmd = cmd.Left(57) + "…"
		    Return cmd
		  Case "WebSearch", "web_search"
		    Return j.Lookup("query", "")
		  Case "WebFetch", "web_fetch"
		    Var url As String = j.Lookup("url", "")
		    If url.Length > 60 Then url = url.Left(57) + "…"
		    Return url
		  Case "TodoWrite", "TodoRead"
		    Return ""
		  Else
		    Return ""
		  End Select
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function LastPathComponent(path As String) As String
		  Var parts() As String = path.Split("/")
		  Var last As String = parts(parts.LastRowIndex)
		  Return If(last <> "", last, path)
		End Function
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mActiveToolInputJSON As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mActiveToolName As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAuthToken As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mStreamedText As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAutoApprove As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mClientSocket As WS.WSClientSocket
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHandshakeDone As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLastSelection As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLockFile As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mEffort As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mMode As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingAskUserQuestionId As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingControlRequestId As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingControlToolInput As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingControlToolUseId As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingDiffs As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingPlanToolUseId As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPort As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mServerSocket As WS.WSServerSocket
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mWSBuffer As String
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
		#tag ViewProperty
			Name="Title"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="SupportsTools"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="IsConnected"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="SessionId"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="SupportsPlanMode"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="SupportsPermissionPrompts"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="SupportsImageInput"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="DefaultModel"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
