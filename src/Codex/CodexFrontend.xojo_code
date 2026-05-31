#tag Class
Protected Class CodexFrontend
Inherits AIFrontend
	#tag Method, Flags = &h0
		Function SessionList(projectPath As String) As String
		  Var sessionsDir As FolderItem = SpecialFolder.UserHome.Child(".codex").Child("sessions")
		  If sessionsDir = Nil Or Not sessionsDir.Exists Then Return "[]"
		  
		  Var sh As New Shell
		  sh.Execute("find " + sessionsDir.ShellPath + " -name ""rollout-*.jsonl"" 2>/dev/null")
		  Var found As String = sh.Result.Trim
		  If found = "" Then Return "[]"
		  
		  Var sessionIds() As String
		  Var sessionTitles() As String
		  Var sessionDates() As String
		  Var sessionMTimes() As Double
		  
		  For Each fpath As String In found.Split(Chr(10))
		    fpath = fpath.Trim
		    If fpath = "" Then Continue
		    Var f As New FolderItem(fpath, FolderItem.PathModes.Native)
		    If f = Nil Or Not f.Exists Then Continue
		    
		    Var fname As String = f.Name
  If fname.Length < 35 Then Continue
  Var sid As String = fname.Mid(29, fname.Length - 35)
  Var sname As String = sid.Left(8) + "…"
  
  Var allText As String = ""
  Try
    Var ts As TextInputStream = TextInputStream.Open(f)
    ts.Encoding = Encodings.UTF8
    allText = ts.ReadAll
    ts.Close
  Catch ioe As IOException
    System.DebugLog("CodexFrontend.SessionList: skipping " + f.Name + " — " + ioe.Message)
    Continue
  End Try
  
  Var lines() As String = allText.Split(Chr(10))
  
  Var scwd As String = ""
  If lines.LastRowIndex >= 0 Then
    Try
      Var metaItem As New JSONItem(lines(0))
      If metaItem.Lookup("type", "") = "session_meta" Then
        Var metaPayload As JSONItem = AsJSONItem(metaItem.Lookup("payload", ""))
        If metaPayload <> Nil Then scwd = metaPayload.Lookup("cwd", "")
      End If
    Catch e As JSONException
      System.DebugLog("CodexFrontend.SessionList: malformed session_meta in " + f.Name)
    End Try
  End If
  If projectPath <> "" And scwd <> "" And scwd <> projectPath Then Continue
  
  If lines.LastRowIndex >= 5 Then
    Try
      Var lineItem As New JSONItem(lines(5))
      If lineItem.Lookup("type", "") = "response_item" Then
        Var linePayload As JSONItem = AsJSONItem(lineItem.Lookup("payload", ""))
        If linePayload <> Nil And linePayload.Lookup("role", "") = "user" Then
          Var contentArr As JSONItem = AsJSONItem(linePayload.Lookup("content", ""))
          If contentArr <> Nil And contentArr.IsArray Then
            Var ci As Integer
            For ci = 0 To contentArr.Count - 1
              Var block As JSONItem = AsJSONItem(contentArr.ValueAt(ci))
              If block <> Nil And block.Lookup("type", "") = "input_text" Then
                Var txt As String = block.Lookup("text", "")
                txt = txt.Trim
                If txt.Length > 10 And txt.Left(1) <> "<" Then
                  If txt.Length > 60 Then txt = txt.Left(60) + "…"
                  sname = txt
                End If
                Exit
              End If
            Next
          End If
        End If
      End If
    Catch e As JSONException
      System.DebugLog("CodexFrontend.SessionList: malformed response_item in " + f.Name)
    End Try
  End If


		    Var md As Date = f.ModificationDate
		    Var dateStr As String = FormatDate(md)
		    
		    sessionIds.Add(sid)
		    sessionTitles.Add(sname)
		    sessionDates.Add(dateStr)
		    sessionMTimes.Add(f.ModificationDate.TotalSeconds)
		  Next
		  
		  Var n As Integer = sessionIds.LastRowIndex
		  For i As Integer = 0 To n - 1
		    Var maxIdx As Integer = i
		    For j As Integer = i + 1 To n
		      If sessionMTimes(j) > sessionMTimes(maxIdx) Then maxIdx = j
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
		      Var swapMTime As Double = sessionMTimes(i)
		      sessionMTimes(i) = sessionMTimes(maxIdx)
		      sessionMTimes(maxIdx) = swapMTime
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
