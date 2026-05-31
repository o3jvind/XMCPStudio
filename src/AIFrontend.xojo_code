#tag Class
Protected Class AIFrontend

	#tag Method, Flags = &h0
		Function SlashCommands(projectPath As String) As String
		  #Pragma Unused projectPath
		  Return "[]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ModeOptions() As String
		  Return "[]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ToolbarItems() As String
		  Return "[" _
		  + "{""id"":""revert"",""label"":""Revert"",""message"":""revert_project""}," _
		  + "{""id"":""build"",""label"":""Build"",""message"":""build_project""}," _
		  + "{""id"":""debug"",""label"":""Debug"",""message"":""run_project""}" _
		  + "]"
		End Function
	#tag EndMethod


	#tag Method, Flags = &h21
		Protected Function FormatDate(d As Date) As String
		  Return d.Year.ToString + "-" _
		  + If(d.Month < 10, "0", "") + d.Month.ToString + "-" _
		  + If(d.Day < 10, "0", "") + d.Day.ToString
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SessionList(projectPath As String) As String
		  #Pragma Unused projectPath
		  Return "[]"
		End Function
	#tag EndMethod


	#tag Method, Flags = &h0
		Function ModelList() As String
		  Return "[]"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SupportsXMCP() As Boolean
		  Return True
		End Function
	#tag EndMethod

End Class
#tag EndClass
