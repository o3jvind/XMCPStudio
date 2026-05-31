#tag DesktopWindow
Begin DesktopWindow MainWindow
   Backdrop        =   0
   BackgroundColor =   &cFFFFFF
   Composite       =   False
   DefaultLocation =   2
   FullScreen      =   False
   HasBackgroundColor=   False
   HasCloseButton  =   True
   HasFullScreenButton=   True
   HasMaximizeButton=   True
   HasMinimizeButton=   True
   HasTitleBar     =   True
   Height          =   800
   ImplicitInstance=   True
   MacProcID       =   0
   MaximumHeight   =   32000
   MaximumWidth    =   32000
   MenuBar         =   796227583
   MenuBarVisible  =   False
   MinimumHeight   =   600
   MinimumWidth    =   800
   Resizeable      =   True
   Title           =   "XMCPStudio"
   Type            =   0
   Visible         =   True
   Width           =   1200
   Begin ChatView TheViewer
      AutoDeactivate  =   True
      Enabled         =   True
      Height          =   800
      Index           =   -2147483648
      InitialParent   =   ""
      mIsReady        =   False
      Left            =   0
      LockBottom      =   True
      LockedInPosition=   False
      LockLeft        =   True
      LockRight       =   True
      LockTop         =   True
      Scope           =   0
      TabIndex        =   0
      TabPanelIndex   =   0
      TabStop         =   True
      Tooltip         =   ""
      Top             =   0
      Visible         =   True
      Width           =   1200
   End
   Begin DesktopCanvas DropOverlay
      AllowAutoDeactivate=   True
      AllowFocus      =   False
      AllowFocusRing  =   False
      AllowTabs       =   False
      Backdrop        =   0
      Enabled         =   True
      Height          =   800
      Index           =   -2147483648
      InitialParent   =   ""
      Left            =   0
      LockBottom      =   True
      LockedInPosition=   False
      LockLeft        =   True
      LockRight       =   True
      LockTop         =   True
      Scope           =   0
      TabIndex        =   1
      TabPanelIndex   =   0
      TabStop         =   False
      Tooltip         =   ""
      Top             =   0
      Transparent     =   True
      Visible         =   True
      Width           =   1200
   End
End
#tag EndDesktopWindow

#tag WindowCode
	#tag Event
		Sub Closing()
		  If TheViewer <> Nil Then
		    TheViewer.mIsReady = False
		  End If
		  Quit
		End Sub
	#tag EndEvent

	#tag Event
		Sub Opening()
		  Me.Title = "XMCPStudio"
		  TheViewer.LoadUI()

		  DropOverlay.AcceptFileDrop("any")
		  mShowingDropZone = False
		End Sub
	#tag EndEvent

	#tag Event
		Sub Resized()
		  LayoutControls()
		  DropOverlay.Width = Me.Width
		  DropOverlay.Height = Me.Height
		End Sub
	#tag EndEvent


	#tag MenuHandler
		Function FileExportSession() As Boolean Handles FileExportSession.Action
		  App.ExportCurrentSession
		  Return True
		End Function
	#tag EndMenuHandler

	#tag MenuHandler
		Function FileOpenProject() As Boolean Handles FileOpenProject.Action
		  App.SwitchProject
		  Return True
		End Function
	#tag EndMenuHandler


	#tag MenuHandler
		Function ProjectRevert() As Boolean Handles ProjectRevert.Action
		  App.HandleUserMessage("revert_project")
		  Return True
		End Function
	#tag EndMenuHandler

	#tag MenuHandler
		Function ProjectBuild() As Boolean Handles ProjectBuild.Action
		  App.HandleUserMessage("build_project")
		  Return True
		End Function
	#tag EndMenuHandler

	#tag MenuHandler
		Function ProjectDebug() As Boolean Handles ProjectDebug.Action
		  App.HandleUserMessage("run_project")
		  Return True
		End Function
	#tag EndMenuHandler

	#tag MenuHandler
		Function HelpXMCPStudio() As Boolean Handles HelpXMCPStudio.Action
		  Var w As New HelpWindow
		  w.LoadHelp()
		  w.Show
		  Return True
		End Function
	#tag EndMenuHandler


	#tag Method, Flags = &h0
		Sub LayoutControls()
		  TheViewer.Left   = 0
		  TheViewer.Top    = 0
		  TheViewer.Width  = Me.Width
		  TheViewer.Height = Me.Height
		End Sub
	#tag EndMethod



	#tag Property, Flags = &h21
		Private mShowingDropZone As Boolean
	#tag EndProperty



#tag EndWindowCode

#tag Events DropOverlay
	#tag Event
		Sub Paint(g As Graphics, areas() As Rect)
		  If Not mShowingDropZone Then Return
		  ' Subtle full-window tint + border glow
		  g.DrawingColor = Color.RGB(99, 102, 241, 220)
		  g.PenSize = 6
		  g.DrawRoundRectangle(4, 4, g.Width - 8, g.Height - 8, 12, 12)
		  ' Centered label
		  g.DrawingColor = Color.RGB(99, 102, 241, 200)
		  g.FontSize = 18
		  g.Bold = True
		  Var txt As String = "Drop image here"
		  Var tw As Double = g.TextWidth(txt)
		  g.DrawText(txt, (g.Width - tw) / 2, g.Height / 2 + 8)
		End Sub
	#tag EndEvent
	#tag Event
		Function DragEnter(obj As DragItem, action As DragItem.Types) As Boolean
		  If obj.FolderItemAvailable Then
		    mShowingDropZone = True
		    Me.Refresh
		  End If
		End Function
	#tag EndEvent
	#tag Event
		Sub DragExit(obj As DragItem, action As DragItem.Types)
		  mShowingDropZone = False
		  Me.Refresh
		End Sub
	#tag EndEvent
	#tag Event
		Sub DropObject(obj As DragItem, action As DragItem.Types)
		  mShowingDropZone = False
		  Me.Refresh
		  If obj.FolderItem = Nil Or Not obj.FolderItem.Exists Then Return
		  Var f As FolderItem = obj.FolderItem
		  Var ext As String = f.Name.NthField(".", f.Name.CountFields(".")).Lowercase
		  Var imageExts() As String = Array("png", "jpg", "jpeg", "gif", "webp")
		  If imageExts.IndexOf(ext) >= 0 Then
		    TheViewer.HandleImageDrop(f)
		  Else
		    TheViewer.EvaluateJavaScript("insertText(" + DBHelper.JSONEscape(f.NativePath) + ");")
		  End If
		End Sub
	#tag EndEvent
	#tag Event
		Function MouseDown(x As Integer, y As Integer) As Boolean
		  Return False
		End Function
	#tag EndEvent
	#tag Event
		Sub MouseUp(x As Integer, y As Integer)
		End Sub
	#tag EndEvent
	#tag Event
		Sub MouseMove(x As Integer, y As Integer)
		End Sub
	#tag EndEvent
#tag EndEvents

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
		Name="Interfaces"
		Visible=true
		Group="ID"
		InitialValue=""
		Type="String"
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
		Name="Width"
		Visible=true
		Group="Size"
		InitialValue="1200"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="Height"
		Visible=true
		Group="Size"
		InitialValue="800"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MinimumWidth"
		Visible=true
		Group="Size"
		InitialValue="800"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MinimumHeight"
		Visible=true
		Group="Size"
		InitialValue="600"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MaximumWidth"
		Visible=true
		Group="Size"
		InitialValue="32000"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MaximumHeight"
		Visible=true
		Group="Size"
		InitialValue="32000"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="Type"
		Visible=true
		Group="Frame"
		InitialValue="0"
		Type="Types"
		EditorType="Enum"
		#tag EnumValues
			"0 - Document"
			"1 - Movable Modal"
			"2 - Modal Dialog"
			"3 - Floating Window"
			"4 - Plain Box"
			"5 - Shadowed Box"
			"6 - Rounded Window"
			"7 - Global Floating Window"
			"8 - Sheet Window"
			"9 - Modeless Dialog"
		#tag EndEnumValues
	#tag EndViewProperty
	#tag ViewProperty
		Name="Title"
		Visible=true
		Group="Frame"
		InitialValue="XMCPStudio"
		Type="String"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="HasCloseButton"
		Visible=true
		Group="Frame"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="HasMaximizeButton"
		Visible=true
		Group="Frame"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="HasMinimizeButton"
		Visible=true
		Group="Frame"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="HasFullScreenButton"
		Visible=true
		Group="Frame"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="HasTitleBar"
		Visible=true
		Group="Frame"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="Resizeable"
		Visible=true
		Group="Frame"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="Composite"
		Visible=false
		Group="OS X (Carbon)"
		InitialValue="False"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MacProcID"
		Visible=false
		Group="OS X (Carbon)"
		InitialValue="0"
		Type="Integer"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="FullScreen"
		Visible=true
		Group="Behavior"
		InitialValue="False"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="DefaultLocation"
		Visible=true
		Group="Behavior"
		InitialValue="2"
		Type="Locations"
		EditorType="Enum"
		#tag EnumValues
			"0 - Default"
			"1 - Parent Window"
			"2 - Main Screen"
			"3 - Parent Window Screen"
			"4 - Stagger"
		#tag EndEnumValues
	#tag EndViewProperty
	#tag ViewProperty
		Name="Visible"
		Visible=true
		Group="Behavior"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="ImplicitInstance"
		Visible=true
		Group="Behavior"
		InitialValue="True"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="HasBackgroundColor"
		Visible=true
		Group="Background"
		InitialValue="False"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="BackgroundColor"
		Visible=true
		Group="Background"
		InitialValue="&cFFFFFF"
		Type="ColorGroup"
		EditorType="ColorGroup"
	#tag EndViewProperty
	#tag ViewProperty
		Name="Backdrop"
		Visible=true
		Group="Background"
		InitialValue=""
		Type="Picture"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MenuBar"
		Visible=true
		Group="Menus"
		InitialValue=""
		Type="DesktopMenuBar"
		EditorType=""
	#tag EndViewProperty
	#tag ViewProperty
		Name="MenuBarVisible"
		Visible=true
		Group="Deprecated"
		InitialValue="False"
		Type="Boolean"
		EditorType=""
	#tag EndViewProperty
#tag EndViewBehavior
