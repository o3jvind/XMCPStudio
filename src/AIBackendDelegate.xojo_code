#tag Interface
Protected Interface AIBackendDelegate
	#tag Method, Flags = &h0
		Sub AppendToken(token As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub FinalizeMessage()
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub RefreshSessions()
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowError(msg As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Function IsReady() As Boolean
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetBackendStatus(title As String, connected As Boolean, supportsTools As Boolean)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowPermissionPrompt(filePath As String, detail As String = "", oldStr As String = "", newStr As String = "")
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowPlanApproval(planText As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowToolActivity(toolName As String, detail As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowUserMessage(text As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub SetModeSelect(mode As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub LoadBackendUI(config As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub EvaluateJavaScript(js As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowDiff(requestId As String, filePath As String, oldContent As String, newContent As String)
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowAskUserQuestion(questionsJSON As String)
	#tag EndMethod

End Interface
#tag EndInterface
