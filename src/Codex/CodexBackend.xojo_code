#tag Class
Protected Class CodexBackend
Inherits AIBackend
	#tag Method, Flags = &h0
		Sub Constructor()
		  Title = "Codex"
		  SupportsTools = True
		  IsConnected = False
		  SupportsPlanMode = False
		  SupportsPermissionPrompts = True
		  SupportsImageInput = True
		  SupportsReasoningEffort = True
		  Models.Add("gpt-5.4")
		  Models.Add("gpt-5.5")
		  DefaultModel = "gpt-5.4"
		  mModel = "gpt-5.4"
		  mMode = "ask"
		  mReasoningEffort = "medium"
		  mNextId = 1
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindCodexSessionFile(uuid As String) As FolderItem
		  Var sessionsDir As FolderItem = SpecialFolder.UserHome.Child(".codex").Child("sessions")
		  If sessionsDir = Nil Or Not sessionsDir.Exists Then Return Nil
		  Var sh As New Shell
		  sh.Execute("find " + sessionsDir.ShellPath + " -name " + ShellQuote("*" + uuid + "*.jsonl") + " 2>/dev/null")
		  Var found As String = sh.Result.Trim
		  If found = "" Then Return Nil
		  Var lines() As String = found.Split(Chr(10))
		  Var firstLine As String = lines(0).Trim
		  If firstLine = "" Then Return Nil
		  Var f As New FolderItem(firstLine, FolderItem.PathModes.Native)
		  If f <> Nil And f.Exists Then Return f
		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionChatJSON(uuid As String) As String
		  Var sessionFile As FolderItem = FindCodexSessionFile(uuid)
		  If sessionFile = Nil Then Return "[]"
		  
		  Var allText As String
		  Try
		    Var ts As TextInputStream = TextInputStream.Open(sessionFile)
		    ts.Encoding = Encodings.UTF8
		    allText = ts.ReadAll
		    ts.Close
		  Catch e As IOException
		    System.DebugLog("CodexBackend.GetSessionChatJSON: " + e.Message)
		    Return "[]"
		  End Try

		  Var result As String = "["
		  Var first As Boolean = True
		  For Each line As String In allText.Split(Chr(10))
		    line = line.Trim
		    If line = "" Then Continue
		    Try
		      Var item As New JSONItem(line)
		      If item.Lookup("type", "") <> "response_item" Then Continue
		      Var payload As JSONItem = AsJSONItem(item.Lookup("payload", ""))
		      If payload = Nil Then Continue
		      Var role As String = payload.Lookup("role", "")
		      If role <> "user" And role <> "assistant" Then Continue
		      Var contentArr As JSONItem = AsJSONItem(payload.Lookup("content", ""))
		      If contentArr = Nil Or Not contentArr.IsArray Then Continue
		      Var text As String = ""
		      For ci As Integer = 0 To contentArr.Count - 1
		        Var block As JSONItem = AsJSONItem(contentArr.ValueAt(ci))
		        If block = Nil Then Continue
		        Var bt As String = block.Lookup("type", "")
		        If bt = "input_text" Or bt = "output_text" Then
		          text = text + block.Lookup("text", "")
		        End If
		      Next
		      text = text.Trim
		      If text = "" Then Continue
		      If text.Left(1) = "<" Then Continue
		      If Not first Then result = result + ","
		      first = False
		      result = result + "{""role"":" + DBHelper.JSONEscape(role) + ",""content"":" + DBHelper.JSONEscape(text) + "}"
		    Catch e As JSONException
		      Continue
		    End Try
		  Next
		  Return result + "]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionsJSON() As String
		  Var indexFile As FolderItem = SpecialFolder.UserHome.Child(".codex").Child("session_index.jsonl")
		  If indexFile = Nil Or Not indexFile.Exists Then Return "[]"
		  
		  Var raw As String = ""
		  Try
		    Var ts As TextInputStream = TextInputStream.Open(indexFile)
		    ts.Encoding = Encodings.UTF8
		    raw = ts.ReadAll
		    ts.Close
		  Catch e As IOException
		    Return "[]"
		  End Try
		  
		  Var sessionIds() As String
		  Var sessionTitles() As String
		  Var sessionDates() As String
		  
		  For Each line As String In raw.Split(Chr(10))
		    line = line.Trim
		    If line = "" Then Continue
		    Try
		      Var item As New JSONItem(line)
		      Var sid As String = item.Lookup("id", "")
		      Var sname As String = item.Lookup("thread_name", "")
		      Var supdated As String = item.Lookup("updated_at", "")
		      If sid = "" Then Continue
		      sessionIds.Add(sid)
		      sessionTitles.Add(If(sname <> "", sname, sid.Left(8) + "…"))
		      sessionDates.Add(supdated.Left(10))
		    Catch e As JSONException
		      Continue
		    End Try
		  Next
		  
		  Var n As Integer = sessionIds.LastRowIndex
		  For i As Integer = 0 To n - 1
		    Var maxIdx As Integer = i
		    For j As Integer = i + 1 To n
		      If sessionDates(j) > sessionDates(maxIdx) Then maxIdx = j
		    Next
		    If maxIdx <> i Then
		      Var swapId As String = sessionIds(i)
		      sessionIds(i) = sessionIds(maxIdx)
		      sessionIds(maxIdx) = swapId
		      Var swapTitle As String = sessionTitles(i)
		      sessionTitles(i) = sessionTitles(maxIdx)
		      sessionTitles(maxIdx) = swapTitle
		      Var swapDate As String = sessionDates(i)
		      sessionDates(i) = sessionDates(maxIdx)
		      sessionDates(maxIdx) = swapDate
		    End If
		  Next
		  
		  Var limit As Integer = If(n + 1 < 50, n + 1, 50)
		  Var result As String = "["
		  Var first As Boolean = True
		  For i As Integer = 0 To limit - 1
		    If Not first Then result = result + ","
		    first = False
		    result = result + "{" _
		    + """uuid"":" + DBHelper.JSONEscape(sessionIds(i)) + "," _
		    + """title"":" + DBHelper.JSONEscape(sessionTitles(i)) + "," _
		    + """date"":" + DBHelper.JSONEscape(sessionDates(i)) _
		    + "}"
		  Next
		  Return result + "]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h5
		Protected Sub HandleLine(json As String)
		  System.DebugLog("Codex stdout line received (" + json.Bytes.ToString + " bytes)")
		  Var root As JSONItem = ParseJSONOrNil(json)
		  If root = Nil Then Return
		  
		  If root.HasName("id") And (root.HasName("result") Or root.HasName("error")) Then
		    HandleResponse(root)
		    Return
		  End If
		  
		  If root.HasName("method") Then
		    Var method As String = root.Lookup("method", "")
		    If root.HasName("id") Then
		      HandleRequest(method, root)
		    Else
		      HandleNotification(method, root)
		    End If
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HandleNotification(method As String, root As JSONItem)
		  Select Case method
		    
		  Case "thread/started"
		    Var threadItem As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    If threadItem <> Nil Then
		      Var threadObj As JSONItem = AsJSONItem(threadItem.Lookup("thread", ""))
		      If threadObj <> Nil Then
		        mThreadId = threadObj.Lookup("id", "")
		        SessionId = mThreadId
		        System.DebugLog("CodexBackend: thread started, id=" + mThreadId)
		        mDelegate.RefreshSessions()
		      End If
		    End If
		    
		  Case "mcpServer/startupStatus/updated"
		    Var sp As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    If sp <> Nil Then
		      Var status As String = sp.Lookup("status", "")
		      If status = "starting" Then
		        mMCPExpectedCount = mMCPExpectedCount + 1
		        System.DebugLog("CodexBackend: MCP server starting, name=" + sp.Lookup("name", "") + " expected=" + mMCPExpectedCount.ToString)
		      ElseIf status = "ready" Or status = "failed" Then
		        mMCPReadyCount = mMCPReadyCount + 1
		        System.DebugLog("CodexBackend: MCP ready count=" + mMCPReadyCount.ToString + "/" + mMCPExpectedCount.ToString + " name=" + sp.Lookup("name", ""))
		        If mMCPReadyCount >= mMCPExpectedCount And mPendingUserMessage <> "" Then
		          If mPendingImageBase64 <> "" Then
		            SendTurnStartWithImage(mPendingUserMessage, mPendingImageBase64, mPendingImageMediaType)
		          Else
		            SendTurnStart(mPendingUserMessage)
		          End If
		          mPendingUserMessage = ""
		          mPendingImageBase64 = ""
		          mPendingImageMediaType = ""
		        End If
		      End If
		    End If
		    
		  Case "turn/started"
		    Var turnParams As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    If turnParams <> Nil Then
		      Var turnObj As JSONItem = AsJSONItem(turnParams.Lookup("turn", ""))
		      If turnObj <> Nil Then mTurnId = turnObj.Lookup("id", "")
		    End If
		    
		  Case "item/started"
		    Var isp As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    If isp <> Nil Then
		      Var itm As JSONItem = AsJSONItem(isp.Lookup("item", ""))
		      If itm <> Nil Then
		        If itm.Lookup("type", "") = "mcpToolCall" Then
		          mLastMCPToolName = itm.Lookup("server", "") + "/" + itm.Lookup("tool", "")
		        ElseIf itm.Lookup("type", "") = "fileChange" Then
		          Var itemId As String = itm.Lookup("id", "")
		          Var changesArr As JSONItem = AsJSONItem(itm.Lookup("changes", ""))
		          If itemId <> "" And changesArr <> Nil And changesArr.IsArray And changesArr.Count > 0 Then
		            Var combined As String = ""
		            For ci As Integer = 0 To changesArr.Count - 1
		              Var ch As JSONItem = AsJSONItem(changesArr.ValueAt(ci))
		              If ch = Nil Then Continue
		              Var chPath As String = ch.Lookup("path", "")
		              Var chDiff As String = ch.Lookup("diff", "")
		              If combined <> "" Then combined = combined + Chr(1)
		              combined = combined + chPath + Chr(0) + chDiff
		            Next
		            mPendingFileChanges.Value(itemId) = combined
		          End If
		        End If
		      End If
		    End If
		    
		  Case "item/agentMessage/delta"
		    Var deltaParams As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    If deltaParams <> Nil Then
		      Var delta As String = deltaParams.Lookup("delta", "")
		      If delta <> "" Then FireOnToken(delta)
		    End If
		    
		  Case "turn/completed"
		    mTurnId = ""
		    If mPendingTmpImage <> Nil Then
		      mPendingTmpImage.Remove
		      mPendingTmpImage = Nil
		    End If
		    Var tcp As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    If tcp <> Nil Then
		      Var turnObj As JSONItem = AsJSONItem(tcp.Lookup("turn", ""))
		      If turnObj <> Nil Then
		        Var status As String = turnObj.Lookup("status", "completed")
		        If status = "failed" Then
		          Var errObj As JSONItem = AsJSONItem(turnObj.Lookup("error", ""))
		          Var errMsg As String = "Turn failed"
		          If errObj <> Nil Then errMsg = errObj.Lookup("message", errMsg)
		          FireOnError(errMsg)
		          Return
		        End If
		      End If
		    End If
		    FireOnDone()
		    
		  End Select
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HandleRequest(method As String, root As JSONItem)
		  Var id As Integer = root.Lookup("id", 0)
		  Select Case method
		    
		  Case "item/commandExecution/requestApproval", "item/fileChange/requestApproval"
		    Var ap As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    Var detail As String = ""
		    Var fcFilePath As String = ""
		    Var fcOldStr As String = ""
		    Var fcNewStr As String = ""
		    If ap <> Nil Then
		      If method = "item/commandExecution/requestApproval" Then
		        Var cmdVal As JSONItem = AsJSONItem(ap.Lookup("command", ""))
		        If cmdVal <> Nil And cmdVal.IsArray Then
		          For i As Integer = 0 To cmdVal.Count - 1
		            If i > 0 Then detail = detail + " "
		            detail = detail + cmdVal.ValueAt(i).StringValue
		          Next
		        Else
		          detail = ap.Lookup("command", "")
		        End If
		      Else
		        Var itemId As String = ap.Lookup("itemId", "")
		        If itemId <> "" And mPendingFileChanges.HasKey(itemId) Then
		          Var stored As String = mPendingFileChanges.Value(itemId)
		          mPendingFileChanges.Remove(itemId)
		          Var segments() As String = stored.Split(Chr(1))
		          Var multiFile As Boolean = segments.Count > 1
		          For Each segment As String In segments
		            Var segPath As String = segment.NthField(Chr(0), 1)
		            Var unifiedDiff As String = segment.NthField(Chr(0), 2)
		            If segPath <> "" Then
		              If fcFilePath <> "" Then fcFilePath = fcFilePath + ", "
		              fcFilePath = fcFilePath + segPath
		              If multiFile Then
		                Var header As String = "--- " + segPath + " ---"
		                If fcOldStr <> "" Then fcOldStr = fcOldStr + Chr(10)
		                fcOldStr = fcOldStr + header
		                If fcNewStr <> "" Then fcNewStr = fcNewStr + Chr(10)
		                fcNewStr = fcNewStr + header
		              End If
		            End If
		            For Each line As String In unifiedDiff.Split(Chr(10))
		              If line.Left(1) = "-" And line.Left(3) <> "---" Then
		                If fcOldStr <> "" Then fcOldStr = fcOldStr + Chr(10)
		                fcOldStr = fcOldStr + line.Middle(1)
		              ElseIf line.Left(1) = "+" And line.Left(3) <> "+++" Then
		                If fcNewStr <> "" Then fcNewStr = fcNewStr + Chr(10)
		                fcNewStr = fcNewStr + line.Middle(1)
		              End If
		            Next
		          Next
		        End If
		      End If
		    End If
		    If mAutoApprove Then
		      Var autoDecision As String = """accept"""
		      Var autoMsg As String = "{""id"":" + id.ToString + ",""result"":{""decision"":" + autoDecision + "}}" + Chr(10)
		      WriteToStdin(autoMsg)
		    Else
		      Var pending As New Dictionary
		      pending.Value("id") = id
		      pending.Value("method") = method
		      pending.Value("detail") = detail
		      pending.Value("filePath") = fcFilePath
		      pending.Value("oldStr") = fcOldStr
		      pending.Value("newStr") = fcNewStr
		      mApprovalQueue.Add(pending)
		      If mApprovalQueue.Count = 1 Then ShowNextApproval()
		    End If
		    
		  Case "mcpServer/elicitation/request"
		    Var ep As JSONItem = AsJSONItem(root.Lookup("params", ""))
		    Var serverName As String = ""
		    If ep <> Nil Then serverName = ep.Lookup("serverName", "")
		    System.DebugLog("CodexBackend: elicitation request id=" + id.ToString + " serverName=" + serverName + " lastTool=" + mLastMCPToolName)
		    If serverName = "xmcp" Then
		      If mAutoApprove Then
		        Var autoMsg As String = "{""id"":" + id.ToString + ",""result"":{""action"":""accept""}}" + Chr(10)
		        WriteToStdin(autoMsg)
		      Else
		        mPendingElicitationId = id
		        mHasPendingElicitation = True
		        mDelegate.ShowPermissionPrompt("xmcp/" + mLastMCPToolName.NthField("/", 2), "")
		      End If
		    Else
		      Var msg As String = "{""id"":" + id.ToString + ",""result"":{""action"":""accept""}}" + Chr(10)
		      WriteToStdin(msg)
		    End If
		    
		  Else
		    System.DebugLog("CodexBackend: unhandled request method=" + method + " id=" + id.ToString)
		    
		  End Select
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HandleResponse(root As JSONItem)
		  Var id As Integer = root.Lookup("id", 0)
		  System.DebugLog("CodexBackend: response id=" + id.ToString)
		  
		  If root.HasName("error") Then
		    Var errMsg As String = ""
		    Var errItem As JSONItem = AsJSONItem(root.Value("error"))
		    If errItem <> Nil Then errMsg = errItem.Lookup("message", "unknown error")
		    FireOnError(errMsg)
		    Return
		  End If
		  
		  If id = mModelListId And mModelListId > 0 Then
		    mModelListId = 0
		    Var resultItem As JSONItem = AsJSONItem(root.Lookup("result", ""))
		    If resultItem <> Nil Then
		      Var dataItem As JSONItem = AsJSONItem(resultItem.Lookup("models", ""))
		      If dataItem <> Nil And dataItem.IsArray And dataItem.Count > 0 Then
		        Models.RemoveAll()
		        DefaultModel = ""
		        For i As Integer = 0 To dataItem.Count - 1
		          Var m As JSONItem = AsJSONItem(dataItem.ValueAt(i))
		          If m = Nil Then Continue
		          Var mid As String = m.Lookup("id", "")
		          If mid = "" Then Continue
		          Models.Add(mid)
		          If DefaultModel = "" Or m.Lookup("isDefault", False) Then DefaultModel = mid
		        Next
		        If mDelegate.IsReady Then
		          mDelegate.LoadBackendUI(App.BuildBackendUIConfig())
		        End If
		      End If
		    End If
		    Return
		  End If

		  If id = 1 Then
		    IsConnected = True
		    If mDelegate.IsReady Then
		      mDelegate.SetBackendStatus(Title, True, SupportsTools)
		    End If
		    SendModelList()
		    If mPendingUserMessage <> "" Then
		      If mThreadId <> "" Then
		        If mPendingImageBase64 <> "" Then
		          SendTurnStartWithImage(mPendingUserMessage, mPendingImageBase64, mPendingImageMediaType)
		        Else
		          SendTurnStart(mPendingUserMessage)
		        End If
		        mPendingUserMessage = ""
		        mPendingImageBase64 = ""
		        mPendingImageMediaType = ""
		      Else
		        SendThreadStart()
		      End If
		    End If
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub LaunchCodex()
		  Var codexPath As String = ResolveCodexPath()
		  If codexPath = "" Then
		    Var dlg As New MessageDialog
		    dlg.Message = "Codex CLI not found"
		    dlg.Explanation = "The Codex CLI does not appear to be installed on this machine." + EndOfLine + EndOfLine + "Visit OpenAI's support pages or search for 'Codex CLI install' for up-to-date installation instructions."
		    dlg.ActionButton.Caption = "OK"
		    Call dlg.ShowModal
		    Return
		  End If
		  System.DebugLog("CodexBackend: using codex at " + codexPath)
		  
		  Var args() As String
		  args.Add("app-server")
		  
		  StartSubprocess(codexPath, args)
		  
		  System.DebugLog("CodexBackend: codex launched, PID=" + mTask.processIdentifier.ToString)
		  
		  SendInitialize()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub NewSession()
		  SessionId = ""
		  mThreadId = ""
		  mTurnId = ""
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendModelList()
		  mModelListId = NextId()
		  Var msg As String = "{""method"":""model/list"",""id"":" + mModelListId.ToString + ",""params"":{}}" + Chr(10)
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function NextId() As Integer
		  mNextId = mNextId + 1
		  Return mNextId
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ShellQuote(value As String) As String
		  Return "'" + value.ReplaceAll("'", "'\''") + "'"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ResolveCodexPath() As String
		  Var candidates() As String
		  candidates.Add(SpecialFolder.UserHome.NativePath + "/.codex/packages/standalone/current/codex")
		  candidates.Add(SpecialFolder.UserHome.NativePath + "/.local/bin/codex")
		  candidates.Add("/opt/homebrew/bin/codex")
		  candidates.Add("/usr/local/bin/codex")
		  For Each p As String In candidates
		    Var fc As New FolderItem(p, FolderItem.PathModes.Native)
		    If fc <> Nil And fc.Exists Then Return p
		  Next
		  Var sh As New Shell
		  sh.Execute("/bin/zsh -lc 'command -v codex' 2>/dev/null")
		  Var found As String = sh.Result.Trim
		  If found <> "" Then Return found
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ResumeSession(uuid As String)
		  SessionId = uuid
		  Shutdown()
		  StartWithResume(mProjectPath, uuid)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendApprovalResponse(allow As Boolean, always As Boolean = False)
		  If mHasPendingElicitation Then
		    mHasPendingElicitation = False
		    Var action As String = If(allow, """accept""", """decline""")
		    Var emsg As String = "{""id"":" + mPendingElicitationId.ToString + ",""result"":{""action"":" + action + "}}" + Chr(10)
		    mPendingElicitationId = 0
		    WriteToStdin(emsg)
		    Return
		  End If
		  If mApprovalQueue.Count = 0 Then Return
		  Var pending As Dictionary = mApprovalQueue(0)
		  mApprovalQueue.RemoveRowAt(0)
		  Var pendingId As Integer = pending.Value("id")
		  If always Then mAutoApprove = True
		  Var decision As String
		  If Not allow Then
		    decision = """decline"""
		  ElseIf always Then
		    decision = """acceptForSession"""
		  Else
		    decision = """accept"""
		  End If
		  Var msg As String = "{""id"":" + pendingId.ToString + ",""result"":{""decision"":" + decision + "}}" + Chr(10)
		  WriteToStdin(msg)
		  If mApprovalQueue.Count > 0 Then ShowNextApproval()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ShowNextApproval()
		  If mApprovalQueue.Count = 0 Then Return
		  Var pending As Dictionary = mApprovalQueue(0)
		  Var method As String = pending.Value("method")
		  If method = "item/commandExecution/requestApproval" Then
		    mDelegate.ShowPermissionPrompt("", pending.Value("detail"))
		  Else
		    mDelegate.ShowPermissionPrompt(pending.Value("filePath"), "", pending.Value("oldStr"), pending.Value("newStr"))
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendInitialize()
		  Var initId As String = "1"
		  Var msg As String = "{""method"":""initialize"",""id"":" + initId _
		  + ",""params"":{""clientInfo"":{""name"":""XMCPStudio"",""title"":""XMCPStudio"",""version"":""1.0""}}}" + Chr(10)
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendMessage(text As String, history() As Dictionary)
		  #Pragma Unused history
		  If mStdinFD < 0 Then
		    FireOnError("Codex not running.")
		    Return
		  End If
		  If mThreadId = "" Then
		    mPendingUserMessage = text
		    SendThreadStart()
		  Else
		    SendTurnStart(text)
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendMessageWithImage(text As String, imageBase64 As String, imageMediaType As String, history() As Dictionary)
		  #Pragma Unused history
		  If mStdinFD < 0 Then
		    FireOnError("Codex not running.")
		    Return
		  End If
		  mPendingImageBase64 = imageBase64
		  mPendingImageMediaType = imageMediaType
		  mPendingUserMessage = text
		  If mThreadId = "" Then
		    SendThreadStart()
		  Else
		    SendTurnStartWithImage(text, imageBase64, imageMediaType)
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendThreadStart()
		  Var id As Integer = NextId()
		  Var cwd As String = DBHelper.JSONEscape(mProjectPath)
		  Var model As String = DBHelper.JSONEscape(mModel)
		  Var resumeClause As String = ""
		  If mThreadId <> "" Then
		    resumeClause = ",""threadId"":" + DBHelper.JSONEscape(mThreadId)
		  End If
		  Var approvalPolicy As String = If(mMode = "ask", """untrusted""", """on-request""")
		  Var msg As String = "{""method"":""thread/start"",""id"":" + id.ToString _
		  + ",""params"":{""model"":" + model _
		  + ",""cwd"":" + cwd _
		  + ",""approvalPolicy"":" + approvalPolicy _
		  + ",""reasoningEffort"":" + DBHelper.JSONEscape(mReasoningEffort) _
		  + resumeClause + "}}" + Chr(10)
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendTurnInterrupt()
		  Var id As Integer = NextId()
		  Var msg As String = "{""method"":""turn/interrupt"",""id"":" + id.ToString _
		  + ",""params"":{""threadId"":" + DBHelper.JSONEscape(mThreadId) _
		  + ",""turnId"":" + DBHelper.JSONEscape(mTurnId) + "}}" + Chr(10)
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendTurnStart(text As String)
		  Var id As Integer = NextId()
		  Var msg As String = "{""method"":""turn/start"",""id"":" + id.ToString _
		  + ",""params"":{""threadId"":" + DBHelper.JSONEscape(mThreadId) _
		  + ",""input"":[{""type"":""text"",""text"":" + DBHelper.JSONEscape(text) + "}]" _
		  + ",""model"":" + DBHelper.JSONEscape(mModel) _
		  + ",""reasoningEffort"":" + DBHelper.JSONEscape(mReasoningEffort) + "}}" + Chr(10)
		  WriteToStdin(msg)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SendTurnStartWithImage(text As String, imageBase64 As String, mediaType As String)
		  Var ext As String = "png"
		  Select Case mediaType
		  Case "image/jpeg"
		    ext = "jpg"
		  Case "image/gif"
		    ext = "gif"
		  Case "image/webp"
		    ext = "webp"
		  End Select
		  Var tmpPath As String = "/tmp/xmcpstudio_img_" + Str(System.Microseconds) + "." + ext
		  Var tmpFile As New FolderItem(tmpPath, FolderItem.PathModes.Native)
		  Var bs As BinaryStream = BinaryStream.Create(tmpFile, True)
		  bs.Write(DecodeBase64(imageBase64))
		  bs.Close

		  Var id As Integer = NextId()
		  Var textBlock As String = "{""type"":""text"",""text"":" + DBHelper.JSONEscape(text) + "}"
		  Var imgBlock As String = "{""type"":""localImage"",""path"":" + DBHelper.JSONEscape(tmpPath) + "}"
		  Var input As String = "[" + textBlock + "," + imgBlock + "]"
		  Var msg As String = "{""method"":""turn/start"",""id"":" + id.ToString _
		  + ",""params"":{""threadId"":" + DBHelper.JSONEscape(mThreadId) _
		  + ",""input"":" + input _
		  + ",""model"":" + DBHelper.JSONEscape(mModel) _
		  + ",""reasoningEffort"":" + DBHelper.JSONEscape(mReasoningEffort) + "}}" + Chr(10)
		  WriteToStdin(msg)
		  mPendingTmpImage = tmpFile
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetAutoApprove(value As Boolean)
		  mAutoApprove = value
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetMode(m As String)
		  mMode = m
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetReasoningEffort(effort As String)
		  mReasoningEffort = effort
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetModel(m As String)
		  mModel = m
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Shutdown()
		  ShutdownSubprocess()
		  IsConnected = False
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Start(projectPath As String)
		  StartWithResume(projectPath, "")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub StartWithResume(projectPath As String, resumeThreadId As String)
		  System.DebugLog("CodexBackend: Start called, model=" + mModel)
		  mProjectPath = projectPath
		  mThreadId = resumeThreadId
		  mTurnId = ""
		  mStdoutBuffer = ""
		  mNextId = 1
		  mModelListId = 0
		  mMCPReadyCount = 0
		  mMCPExpectedCount = 0
		  mAutoApprove = False
		  mApprovalQueue.ResizeTo(-1)
		  mPendingFileChanges = New Dictionary
		  mPendingElicitationId = 0
		  mHasPendingElicitation = False
		  mLastMCPToolName = ""
		  
		  LaunchCodex()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub StopGeneration()
		  If mTurnId <> "" And mThreadId <> "" Then
		    SendTurnInterrupt()
		  End If
		  FireOnDone()
		  Shutdown()
		  Start(mProjectPath)
		End Sub
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mAutoApprove As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHasPendingElicitation As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLastMCPToolName As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mMCPExpectedCount As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mMCPReadyCount As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mMode As String

	#tag EndProperty

	#tag Property, Flags = &h21
		Private mReasoningEffort As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mNextId As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mModelListId As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mApprovalQueue() As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingElicitationId As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingImageBase64 As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingImageMediaType As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingTmpImage As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingUserMessage As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mThreadId As String
	#tag EndProperty


	#tag Property, Flags = &h21
		Private mTurnId As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingFileChanges As Dictionary
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
			EditorType="MultiLineEditor"
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
			EditorType="MultiLineEditor"
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
			EditorType="MultiLineEditor"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
