#tag Class
Protected Class WSClientSocket
Inherits TCPSocket
	#tag Event
		Sub DataAvailable()
		  Var data As String = Me.ReadAll
		  If mDelegate = Nil Then Return
		  mDelegate.OnClientData(Me, data)
		End Sub
	#tag EndEvent

	#tag Event
		Sub Error(err As RuntimeException)
		  If mDelegate = Nil Then Return
		  mDelegate.OnClientError(Me, err)
		End Sub
	#tag EndEvent


	#tag Method, Flags = &h0
		Sub SetDelegate(d As WSClientDelegate)
		  mDelegate = d
		End Sub
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mDelegate As WSClientDelegate
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
			InitialValue=""
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
			Name="Address"
			Visible=true
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Port"
			Visible=true
			Group="Behavior"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
