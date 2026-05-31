#tag DesktopWindow
Begin DesktopWindow JobEditorWindow
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
   Title           =   "Job"
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
		Sub LoadJob(id As Integer, name As String, prompt As String, description As String, tags As String)
		  mJobId = id
		  mDirty = False
		  mCachedName        = name
		  mCachedPrompt      = prompt
		  mCachedDescription = description
		  mCachedTags        = tags
		  Me.Title = If(name <> "", name, "Job")
		  #If DebugBuild Then
		    EditorView.developerExtrasEnabled = True
		  #EndIf
		  EditorView.AddScriptMessageHandler("saveJob")
		  EditorView.AddScriptMessageHandler("deleteJob")
		  EditorView.AddScriptMessageHandler("closeEditor")
		  EditorView.AddScriptMessageHandler("setDirty")

		  Var css  As String = EditorHelper.LoadFiles(Array("web-assets/css/variables.css", "web-assets/css/job-editor.css"))
		  Var js   As String = EditorHelper.LoadFiles(Array("web-assets/js/vendor/marked.min.js", "web-assets/js/job-editor.js"))
		  Var html As String = EditorHelper.BuildEditorHTML(css, js, BuildJobDataScript(id, name, prompt, description, tags))
		  EditorView.LoadHTML(html, "")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BuildJobDataScript(id As Integer, name As String, prompt As String, description As String, tags As String) As String
		  Return "var JOB_DATA = {id:" + id.ToString _
		    + ",name:" + DBHelper.JSONEscape(name) _
		    + ",prompt:" + DBHelper.JSONEscape(prompt) _
		    + ",description:" + DBHelper.JSONEscape(description) _
		    + ",tags:" + DBHelper.JSONEscape(tags) _
		    + "};"
		End Function
	#tag EndMethod

	#tag Event
		Function CancelClosing(appQuitting As Boolean) As Boolean
		  If appQuitting Or Not mDirty Then Return False
		  Var choice As Integer = EditorHelper.UnsavedChangesDialog()
		  If choice = 0 Then
		    Var ok As Boolean
		    If mJobId > 0 Then
		      ok = DBHelper.UpdateJob(mJobId, mCachedName, mCachedPrompt, mCachedDescription, mCachedTags)
		    Else
		      ok = DBHelper.CreateJob(mCachedName, mCachedPrompt, mCachedDescription, mCachedTags)
		    End If
		    If Not ok Then
		      ' DB save failed — DBHelper already showed the user a dialog.
		      Return True
		    End If
		    MainWindow.TheViewer.RefreshJobs()
		    mDirty = False
		    Return False
		  End If
		  Return choice = 1
		End Function
	#tag EndEvent

	#tag Property, Flags = &h21
		Private mJobId As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDirty As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedName As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedPrompt As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedDescription As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCachedTags As String
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
		  Case "saveJob"
		    Var d As Dictionary = Body
		    Var jobName        As String = d.Lookup("name", "")
		    Var jobPrompt      As String = d.Lookup("prompt", "")
		    Var jobDescription As String = d.Lookup("description", "")
		    Var jobTags        As String = d.Lookup("tags", "")
		    Var ok As Boolean
		    If Self.mJobId > 0 Then
		      ok = DBHelper.UpdateJob(Self.mJobId, jobName, jobPrompt, jobDescription, jobTags)
		    Else
		      ok = DBHelper.CreateJob(jobName, jobPrompt, jobDescription, jobTags)
		    End If
		    ' Only clear dirty + refresh sidebar + retitle the window on success.
		    ' On failure, DBHelper has already shown the user a dialog; we keep
		    ' the unsaved-changes state so they can retry without losing edits.
		    If ok Then
		      Self.mDirty = False
		      MainWindow.TheViewer.RefreshJobs()
		      Self.Title = If(jobName <> "", jobName, "Job")
		    End If
		  Case "deleteJob"
		    If Self.mJobId > 0 Then
		      If Not DBHelper.DeleteJob(Self.mJobId) Then Return
		    End If
		    Self.mDirty = False
		    MainWindow.TheViewer.RefreshJobs()
		    Self.Close
		  Case "closeEditor"
		    Self.Close
		  Case "setDirty"
		    Var sd As Dictionary = Body
		    Self.mDirty             = sd.Lookup("dirty", False)
		    Self.mCachedName        = sd.Lookup("name",        Self.mCachedName)
		    Self.mCachedPrompt      = sd.Lookup("prompt",      Self.mCachedPrompt)
		    Self.mCachedDescription = sd.Lookup("description", Self.mCachedDescription)
		    Self.mCachedTags        = sd.Lookup("tags",        Self.mCachedTags)
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

