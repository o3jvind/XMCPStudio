#tag Class
Protected Class AIBackend

	#tag Property, Flags = &h0
		Title As String
	#tag EndProperty

	#tag Property, Flags = &h0
		SupportsTools As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		IsConnected As Boolean
	#tag EndProperty



	#tag Property, Flags = &h0
		SessionId As String
	#tag EndProperty

	#tag Property, Flags = &h0
		SupportsPlanMode As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		SupportsPermissionPrompts As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		SupportsImageInput As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		SupportsReasoningEffort As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		Models() As String
	#tag EndProperty

	#tag Property, Flags = &h0
		DefaultModel As String
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mTask As NSTaskMBS
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStdinPipe As NSPipeMBS
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStdoutPipe As NSPipeMBS
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStderrPipe As NSPipeMBS
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStdinFD As Integer
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStdoutFD As Integer
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStderrFD As Integer
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStdoutBuffer As String
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStdoutHandle As NSFileHandleMBS
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mStderrHandle As NSFileHandleMBS
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mStdoutObserver As NSNotificationObserverMBS
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mStderrObserver As NSNotificationObserverMBS
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mProjectPath As String
	#tag EndProperty

	#tag Property, Flags = &h4
		Protected mModel As String
	#tag EndProperty

	#tag Method, Flags = &h0
		Sub Constructor()
		  Title = "Unknown"
		  SupportsTools = False
		  IsConnected = False
		  SessionId = ""
		  SupportsPlanMode = False
		  SupportsPermissionPrompts = False
		  SupportsImageInput = False
		  SupportsReasoningEffort = False
		  DefaultModel = ""
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetDelegate(d As AIBackendDelegate)
		  mDelegate = d
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Start(projectPath As String)
		  #Pragma Unused projectPath
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Shutdown()
		  Return
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendMessage(text As String, history() As Dictionary)
		  #Pragma Unused text
		  #Pragma Unused history
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SendMessageWithImage(text As String, imageBase64 As String, imageMediaType As String, history() As Dictionary)
		  #Pragma Unused text
		  #Pragma Unused imageBase64
		  #Pragma Unused imageMediaType
		  #Pragma Unused history
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub StopGeneration()
		  Return
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetModel(m As String)
		  #Pragma Unused m
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetMode(m As String)
		  #Pragma Unused m
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetReasoningEffort(effort As String)
		  #Pragma Unused effort
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub NewSession()
		  Return
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ResumeSession(uuid As String)
		  #Pragma Unused uuid
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionsJSON() As String
		  Return "[]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetSessionChatJSON(uuid As String) As String
		  #Pragma Unused uuid
		  Return "[]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OnDiffAccepted(requestId As String, filePath As String)
		  #Pragma Unused requestId
		  #Pragma Unused filePath
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OnDiffRejected(requestId As String)
		  #Pragma Unused requestId
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub FireOnToken(token As String)
		  If mDelegate <> Nil Then mDelegate.AppendToken(token)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub FireOnDone()
		  If mDelegate <> Nil Then mDelegate.FinalizeMessage()
		  If mDelegate <> Nil Then mDelegate.RefreshSessions()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub FireOnError(msg As String)
		  If mDelegate <> Nil And mDelegate.IsReady Then
		    mDelegate.ShowError(msg)
		  Else
		    mPendingError = msg
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub FlushPendingError()
		  If mDelegate <> Nil And mPendingError <> "" Then
		    mDelegate.ShowError(mPendingError)
		    mPendingError = ""
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub StartSubprocess(path As String, args() As String)
		  mTask = New NSTaskMBS
		  mTask.launchPath = path
		  mTask.setArguments(args)
		  mTask.currentDirectoryPath = mProjectPath

		  Var env As New Dictionary
		  Var sh As New Shell
		  sh.Execute("env")
		  Var envLines() As String = sh.Result.Split(Chr(10))
		  For Each envLine As String In envLines
		    Var eqPos As Integer = envLine.IndexOf("=")
		    If eqPos > 0 Then
		      env.Value(envLine.Left(eqPos)) = envLine.Middle(eqPos + 1)
		    End If
		  Next
		  mTask.environment = env

		  mStdinPipe = New NSPipeMBS
		  mStdoutPipe = New NSPipeMBS
		  mStderrPipe = New NSPipeMBS
		  mTask.setStandardInput(mStdinPipe)
		  mTask.setStandardOutput(mStdoutPipe)
		  mTask.setStandardError(mStderrPipe)
		  mStdinFD = mStdinPipe.fileHandleForWriting.fileDescriptor
		  mStdoutFD = mStdoutPipe.fileHandleForReading.fileDescriptor
		  mStderrFD = mStderrPipe.fileHandleForReading.fileDescriptor

		  mTask.launch()

		  mStdoutBuffer = ""

		  mStdoutHandle = NSFileHandleMBS.fileHandleWithFileDescriptor(mStdoutFD)
		  mStderrHandle = NSFileHandleMBS.fileHandleWithFileDescriptor(mStderrFD)

		  Var center As NSNotificationCenterMBS = NSNotificationCenterMBS.defaultCenter

		  mStdoutObserver = New NSNotificationObserverMBS
		  AddHandler mStdoutObserver.GotNotification, WeakAddressOf StdoutDataAvailable
		  center.addObserver(mStdoutObserver, NSFileHandleMBS.NSFileHandleDataAvailableNotification, mStdoutHandle)

		  mStderrObserver = New NSNotificationObserverMBS
		  AddHandler mStderrObserver.GotNotification, WeakAddressOf StderrDataAvailable
		  center.addObserver(mStderrObserver, NSFileHandleMBS.NSFileHandleDataAvailableNotification, mStderrHandle)

		  mStdoutHandle.waitForDataInBackgroundAndNotify
		  mStderrHandle.waitForDataInBackgroundAndNotify
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub WriteToStdin(msg As String)
		  If mStdinFD < 0 Then Return
		  Declare Function unix_write Lib "libc.dylib" Alias "write" (fd As Integer, buf As Ptr, count As Integer) As Integer
		  Var total As Integer = msg.Bytes
		  Var written As Integer = 0
		  While written < total
		    Var chunk As String = msg.Middle(written, total - written)
		    Var mb As New MemoryBlock(chunk.Bytes)
		    mb.StringValue(0, chunk.Bytes) = chunk
		    Var n As Integer = unix_write(mStdinFD, mb, chunk.Bytes)
		    If n <= 0 Then written = total
		    written = written + n
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub StdoutDataAvailable(observer As NSNotificationObserverMBS, notification As NSNotificationMBS)
		  #Pragma Unused observer
		  #Pragma Unused notification
		  If mStdoutFD < 0 Then Return
		  Declare Function unix_read Lib "libc.dylib" Alias "read" (fd As Integer, buf As Ptr, count As Integer) As Integer

		  Var mb As New MemoryBlock(65536)
		  Var n As Integer = unix_read(mStdoutFD, mb, 65536)
		  If n = 0 Then
		    System.DebugLog("AIBackend: stdout EOF — process exited")
		    mStdoutFD = -1
		    Return
		  End If
		  If n > 0 Then
		    Var data As String = mb.StringValue(0, n)
		    mStdoutBuffer = mStdoutBuffer + data
		    Var lines() As String = mStdoutBuffer.Split(Chr(10))
		    mStdoutBuffer = lines(lines.LastRowIndex)
		    lines.RemoveRowAt(lines.LastRowIndex)
		    For Each line As String In lines
		      line = line.Trim
		      If line <> "" Then HandleLine(line)
		    Next
		  End If

		  If mStdoutHandle <> Nil Then mStdoutHandle.waitForDataInBackgroundAndNotify
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub StderrDataAvailable(observer As NSNotificationObserverMBS, notification As NSNotificationMBS)
		  #Pragma Unused observer
		  #Pragma Unused notification
		  If mStderrFD < 0 Then Return
		  Declare Function unix_read Lib "libc.dylib" Alias "read" (fd As Integer, buf As Ptr, count As Integer) As Integer

		  Var emb As New MemoryBlock(4096)
		  Var en As Integer = unix_read(mStderrFD, emb, 4096)
		  If en > 0 Then
		    Var edata As String = emb.StringValue(0, en)
		    If edata.Trim <> "" Then
		      System.DebugLog("Backend stderr received (" + en.ToString + " bytes)")
		    End If
		  End If

		  If mStderrHandle <> Nil Then mStderrHandle.waitForDataInBackgroundAndNotify
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub HandleLine(json As String)
		  #Pragma Unused json
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Sub ShutdownSubprocess()
		  Var center As NSNotificationCenterMBS = NSNotificationCenterMBS.defaultCenter
		  If mStdoutObserver <> Nil Then
		    center.removeObserver(mStdoutObserver)
		    mStdoutObserver = Nil
		  End If
		  If mStderrObserver <> Nil Then
		    center.removeObserver(mStderrObserver)
		    mStderrObserver = Nil
		  End If
		  mStdoutHandle = Nil
		  mStderrHandle = Nil

		  If mTask <> Nil Then
		    If mTask.isRunning Then mTask.terminate()
		    mTask = Nil
		  End If
		  mStdinPipe = Nil
		  mStdoutPipe = Nil
		  mStderrPipe = Nil
		  mStdinFD = -1
		  mStdoutFD = -1
		  mStderrFD = -1
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h4
		Protected Function ParseJSONOrNil(json As String) As JSONItem
		  Try
		    Return New JSONItem(json)
		  Catch e As JSONException
		    Return Nil
		  End Try
		End Function
	#tag EndMethod


	#tag Property, Flags = &h4
		Protected mDelegate As AIBackendDelegate
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPendingError As String
	#tag EndProperty

End Class
#tag EndClass
