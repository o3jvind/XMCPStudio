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
		  Var raw As String = sh.Result.Trim
		  Return HexDecodeIfNeeded(raw)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function HexDecodeIfNeeded(s As String) As String
		  // The macOS `security` CLI hex-encodes non-ASCII password bytes (UTF-8)
		  // when reading via -w. Detect and decode so callers get the original value.
		  // Guard: must be even-length and all hex digits.
		  If s.Length = 0 Or (s.Length Mod 2) <> 0 Then Return s
		  Var lower As String = s.Lowercase
		  For i As Integer = 0 To s.Length - 1
		    Var c As String = lower.Middle(i, 1)
		    If (c < "0" Or c > "9") And (c < "a" Or c > "f") Then Return s
		  Next
		  // Only substitute when at least one byte > 0x7F is present — that's the
		  // signature of a UTF-8 multi-byte sequence. Pure-ASCII keychain values
		  // (year numbers, MBS keys, etc.) are never hex-encoded by `security`.
		  Var hasHighByte As Boolean = False
		  For i As Integer = 0 To (s.Length \ 2) - 1
		    If Integer.FromHex(s.Middle(i * 2, 2)) > 127 Then
		      hasHighByte = True
		      Exit
		    End If
		  Next
		  If Not hasHighByte Then Return s
		  Var mb As New MemoryBlock(s.Length \ 2)
		  For i As Integer = 0 To mb.Size - 1
		    mb.UInt8Value(i) = Integer.FromHex(s.Middle(i * 2, 2))
		  Next
		  Return mb.StringValue(0, mb.Size).DefineEncoding(Encodings.UTF8)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ShellQuote(value As String) As String
		  Return "'" + value.ReplaceAll("'", "'\''") + "'"
		End Function
	#tag EndMethod

End Module
#tag EndModule
