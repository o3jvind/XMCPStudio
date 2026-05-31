#tag DesktopWindow
Begin DesktopWindow ProjectPickerWindow
   Backdrop        =   0
   BackgroundColor =   &cFFFFFF
   Composite       =   False
   DefaultLocation =   2
   FullScreen      =   False
   HasBackgroundColor=   False
   HasCloseButton  =   True
   HasFullScreenButton=   False
   HasMaximizeButton=   False
   HasMinimizeButton=   False
   HasTitleBar     =   True
   Height          =   320
   ImplicitInstance=   False
   MacProcID       =   0
   MaximumHeight   =   32000
   MaximumWidth    =   32000
   MenuBar         =   796227583
   MenuBarVisible  =   False
   MinimumHeight   =   240
   MinimumWidth    =   420
   Resizeable      =   True
   Title           =   "Choose a Xojo Project"
   Type            =   0
   Visible         =   True
   Width           =   520
   Begin DesktopLabel HeaderLabel
      AllowAutoDeactivate=   True
      Bold            =   False
      Enabled         =   True
      FontName        =   "System"
      FontSize        =   0.0
      FontUnit        =   0
      Height          =   34
      Index           =   -2147483648
      Italic          =   False
      Left            =   16
      LockBottom      =   False
      LockedInPosition=   False
      LockLeft        =   True
      LockRight       =   True
      LockTop         =   True
      Multiline       =   True
      Scope           =   0
      Selectable      =   False
      TabIndex        =   0
      TabPanelIndex   =   0
      TabStop         =   True
      Text            =   "Multiple Xojo project files were found. Choose one to open:"
      TextAlignment   =   0
      TextColor       =   &c000000
      Tooltip         =   ""
      Top             =   16
      Transparent     =   False
      Underline       =   False
      Visible         =   True
      Width           =   488
   End
   Begin DesktopListBox ProjectList
      AllowAutoDeactivate=   True
      AllowAutoHideScrollbars=   True
      AllowExpandableRows=   False
      AllowFocusRing  =   True
      AllowResizableColumns=   False
      AllowRowDragging=   False
      AllowRowReordering=   False
      Bold            =   False
      Border          =   True
      ColumnCount     =   1
      ColumnsResizable=   False
      ColumnWidths    =   ""
      DefaultRowHeight=   -1
      Enabled         =   True
      FontName        =   "System"
      FontSize        =   0.0
      FontUnit        =   0
      GridLinesHorizontal=   0
      GridLinesVertical=   0
      HasHeader       =   False
      Header0         =   "Project"
      Height          =   200
      Index           =   -2147483648
      InitialValue    =   ""
      Italic          =   False
      Left            =   16
      LockBottom      =   True
      LockedInPosition=   False
      LockLeft        =   True
      LockRight       =   True
      LockTop         =   True
      RequiresSelection=   True
      Scope           =   0
      ScrollbarHorizontal=   False
      ScrollBarVertical=   True
      SelectionType   =   0
      TabIndex        =   1
      TabPanelIndex   =   0
      TabStop         =   True
      Tooltip         =   ""
      Top             =   60
      Underline       =   False
      Visible         =   True
      Width           =   488
   End
   Begin DesktopButton CancelButton
      AllowAutoDeactivate=   True
      Bold            =   False
      Cancel          =   True
      Default         =   False
      Enabled         =   True
      FontName        =   "System"
      FontSize        =   0.0
      FontUnit        =   0
      Height          =   24
      Index           =   -2147483648
      Italic          =   False
      Left            =   336
      LockBottom      =   True
      LockedInPosition=   False
      LockLeft        =   False
      LockRight       =   True
      LockTop         =   False
      Scope           =   0
      TabIndex        =   2
      TabPanelIndex   =   0
      TabStop         =   True
      Tooltip         =   ""
      Top             =   276
      Underline       =   False
      Visible         =   True
      Width           =   80
      Caption         =   "Cancel"
   End
   Begin DesktopButton OKButton
      AllowAutoDeactivate=   True
      Bold            =   False
      Cancel          =   False
      Default         =   True
      Enabled         =   True
      FontName        =   "System"
      FontSize        =   0.0
      FontUnit        =   0
      Height          =   24
      Index           =   -2147483648
      Italic          =   False
      Left            =   424
      LockBottom      =   True
      LockedInPosition=   False
      LockLeft        =   False
      LockRight       =   True
      LockTop         =   False
      Scope           =   0
      TabIndex        =   3
      TabPanelIndex   =   0
      TabStop         =   True
      Tooltip         =   ""
      Top             =   276
      Underline       =   False
      Visible         =   True
      Width           =   80
      Caption         =   "Open"
   End
End
#tag EndDesktopWindow

#tag WindowCode
	#tag Method, Flags = &h0
		Function PickFrom(candidates() As FolderItem) As FolderItem
		  // Populate the list, show modal, return the chosen file or Nil on cancel.
		  mCandidates = candidates
		  mChosen = Nil

		  ProjectList.RemoveAllRows
		  For Each f As FolderItem In candidates
		    If f <> Nil Then ProjectList.AddRow(f.Name)
		  Next f
		  If ProjectList.RowCount > 0 Then ProjectList.SelectedRowIndex = 0

		  Self.ShowModal

		  Return mChosen
		End Function
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mCandidates() As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mChosen As FolderItem
	#tag EndProperty
#tag EndWindowCode

#tag Events OKButton
	#tag Event
		Sub Pressed()
		  Var idx As Integer = ProjectList.SelectedRowIndex
		  If idx >= 0 And idx <= mCandidates.LastIndex Then
		    mChosen = mCandidates(idx)
		  End If
		  Self.Close
		End Sub
	#tag EndEvent
#tag EndEvents

#tag Events CancelButton
	#tag Event
		Sub Pressed()
		  mChosen = Nil
		  Self.Close
		End Sub
	#tag EndEvent
#tag EndEvents

#tag Events ProjectList
	#tag Event
		Sub DoublePressed()
		  // Same as clicking OK.
		  Var idx As Integer = ProjectList.SelectedRowIndex
		  If idx >= 0 And idx <= mCandidates.LastIndex Then
		    mChosen = mCandidates(idx)
		  End If
		  Self.Close
		End Sub
	#tag EndEvent
#tag EndEvents
