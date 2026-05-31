#tag DesktopWindow
Begin DesktopWindow NoteEditorWindow
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
   Height          =   700
   ImplicitInstance=   False
   MacProcID       =   0
   MaximumHeight   =   32000
   MaximumWidth    =   32000
   MenuBar         =   796227583
   MenuBarVisible  =   False
   MinimumHeight   =   400
   MinimumWidth    =   500
   Resizeable      =   True
   Title           =   "Note"
   Type            =   0
   Visible         =   True
   Width           =   900
   Begin DesktopWKWebViewControlMBS EditorView
      AutoDeactivate  =   True
      Enabled         =   True
      Height          =   700
      Index           =   -2147483648
      InitialParent   =   ""
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
      Width           =   900
   End
End
#tag EndDesktopWindow

#tag WindowCode
	#tag Event
		Sub Resized()
		  EditorView.Width  = Me.Width
		  EditorView.Height = Me.Height
		End Sub
	#tag EndEvent

	#tag Method, Flags = &h0
		Sub LoadNote(id As Integer, title As String, body As String, tags As String, description As String, scope As String)
		  mNoteId = id
		  mDirty = False
		  mCachedTitle       = title
		  mCachedBody        = body
		  mCachedTags        = tags
		  mCachedDescription = description
		  mCachedScope       = scope
		  Me.Title = If(title <> "", title, "Note")
		  #If DebugBuild Then
		    EditorView.developerExtrasEnabled = True
		  #EndIf
		  EditorView.AddScriptMessageHandler("saveNote")
		  EditorView.AddScriptMessageHandler("deleteNote")
		  EditorView.AddScriptMessageHandler("closeEditor")
		  EditorView.AddScriptMessageHandler("setDirty")

		  Var css  As String = EditorHelper.LoadFiles(Array("web-assets/css/variables.css", "web-assets/css/note-editor.css"))
		  Var js   As String = EditorHelper.LoadFiles(Array("web-assets/js/vendor/marked.min.js", "web-assets/js/note-editor.js"))
		  Var html As String = EditorHelper.BuildEditorHTML(css, js, BuildNoteDataScript(id, title, body, tags, description, scope))
		  EditorView.LoadHTML(html, "")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BuildNoteDataScript(id As Integer, title As String, body As String, tags As String, description As String, scope As String) As String
		  Return "var NOTE_DATA = {id:" + id.ToString _
		    + ",title:" + DBHelper.JSONEscape(title) _
		    + ",body:" + DBHelper.JSONEscape(body) _
		    + ",tags:" + DBHelper.JSONEscape(tags) _
		    + ",description:" + DBHelper.JSONEscape(description) _
		    + ",scope:" + DBHelper.JSONEscape(scope) _
		    + "};"
		End Function
	#tag EndMethod

	#tag Event
		Function CancelClosing(appQuitting As Boolean) As Boolean
		  If appQuitting Or Not mDirty Then Return False
		  Var choice As Integer = EditorHelper.UnsavedChangesDialog()
		  If choice = 0 Then
		    Var ok As Boolean
		    If mNoteId > 0 Then
		      ok = DBHelper.UpdateNote(mNoteId, mCachedTitle, mCachedBody, mCachedTags, mCachedDescription, mCachedScope, App.CurrentProjectPath())
		    Else
		      ok = DBHelper.CreateNote(mCachedTitle, mCachedBody, mCachedTags, mCachedDescription, mCachedScope, App.CurrentProjectPath())
		    End If
		    If Not ok Then
		      ' DB save failed — keep the window open so edits aren't lost.
		      Return True
		    End If
		    MainWindow.TheViewer.RefreshNotes()
		    mDirty = False
		    Return False
		  End If
		  Return choice = 1
		End Function
	#tag EndEvent

	#tag Property, Flags = &h21
		Private mNoteId As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDirty As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedTitle As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedBody As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedTags As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedDescription As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedScope As String
	#tag EndProperty

	#tag MenuHandler
		Function FileCloseWindow() As Boolean Handles FileCloseWindow.MenuItemSelected
		  ' ⌘W closes this editor window. The CancelClosing event handles
		  ' the dirty-check prompt for unsaved changes.
		  Self.Close
		  Return True
		End Function
	#tag EndMenuHandler

	#tag Method, Flags = &h0
		Sub ApplyTheme(theme As String)
		  EditorView.EvaluateJavaScript(EditorHelper.ApplyThemeScript(theme))
		End Sub
	#tag EndMethod
#tag EndWindowCode

#tag Events EditorView
	#tag Event
		Sub didReceiveScriptMessage(Body as Variant, name as String)
		  Select Case name
		  Case "saveNote"
		    Var d As Dictionary = Body
		    Var noteTitle       As String = d.Lookup("title", "")
		    Var noteBody        As String = d.Lookup("body", "")
		    Var noteTags        As String = d.Lookup("tags", "")
		    Var noteDescription As String = d.Lookup("description", "")
		    Var noteScope       As String = d.Lookup("scope", "global")
		    Var ok As Boolean
		    If Self.mNoteId > 0 Then
		      ok = DBHelper.UpdateNote(Self.mNoteId, noteTitle, noteBody, noteTags, noteDescription, noteScope, App.CurrentProjectPath())
		    Else
		      ok = DBHelper.CreateNote(noteTitle, noteBody, noteTags, noteDescription, noteScope, App.CurrentProjectPath())
		    End If
		    ' On failure, keep dirty state so the user can retry without losing edits.
		    If ok Then
		      Self.mDirty = False
		      MainWindow.TheViewer.RefreshNotes()
		      Self.Title = If(noteTitle <> "", noteTitle, "Note")
		    End If
		  Case "deleteNote"
		    If Self.mNoteId > 0 Then
		      If Not DBHelper.DeleteNote(Self.mNoteId) Then Return
		    End If
		    Self.mDirty = False
		    MainWindow.TheViewer.RefreshNotes()
		    Self.Close
		  Case "closeEditor"
		    Self.Close
		  Case "setDirty"
		    Var sd As Dictionary = Body
		    Self.mDirty              = sd.Lookup("dirty", False)
		    Self.mCachedTitle        = sd.Lookup("title",       Self.mCachedTitle)
		    Self.mCachedBody         = sd.Lookup("body",        Self.mCachedBody)
		    Self.mCachedTags         = sd.Lookup("tags",        Self.mCachedTags)
		    Self.mCachedDescription  = sd.Lookup("description", Self.mCachedDescription)
		    Self.mCachedScope        = sd.Lookup("scope",       Self.mCachedScope)
		  End Select
		End Sub
	#tag EndEvent

	#tag Event
		Function runJavaScriptConfirmPanel(initiatedByFrame As WKFrameInfoMBS, message As String) As Boolean
		  Var d As New MessageDialog
		  d.Icon = MessageDialog.GraphicCaution
		  d.ActionButton.Caption = "OK"
		  d.CancelButton.Visible = True
		  d.Message = message
		  Return d.ShowModal = d.ActionButton
		End Function
	#tag EndEvent

	#tag Event
		Sub decidePolicyForNavigationAction(navigationAction As WKNavigationActionMBS, decisionHandler As WKPolicyForNavigationActionDecisionHandlerMBS)
		  Var url As String = If(navigationAction <> Nil And navigationAction.request <> Nil, navigationAction.request.URL, "")
		  If url.Left(7) = "http://" Or url.Left(8) = "https://" Then
		    ShowURL(url)
		    decisionHandler.cancel
		  Else
		    decisionHandler.allow
		  End If
		End Sub
	#tag EndEvent
#tag EndEvents

