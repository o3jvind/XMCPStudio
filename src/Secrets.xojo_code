#tag Module
Protected Module Secrets

	#tag Method, Flags = &h0
		Function Get(service As String, account As String) As String
		  #If DebugBuild Then
		    Return KeychainGet(service, account)
		  #Else
		    Return SecretsBuiltin.Get(service + "." + account)
		  #EndIf
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetMBSRegistration() As String()
		  Var r() As String
		  r.Add(Get("MBS", "Owner"))
		  r.Add(Get("MBS", "Product"))
		  r.Add(Get("MBS", "Year"))
		  r.Add(Get("MBS", "Key"))
		  Return r
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function KeychainGet(service As String, account As String) As String
		  Var sh As New Shell
		  sh.Execute("security find-generic-password -s " + ShellQuote(service) + _
		    " -a " + ShellQuote(account) + " -w 2>/dev/null")
		  Return sh.Result.Trim
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ShellQuote(value As String) As String
		  Return "'" + value.ReplaceAll("'", "'\''") + "'"
		End Function
	#tag EndMethod

End Module
#tag EndModule
