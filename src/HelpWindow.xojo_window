#tag DesktopWindow
Begin DesktopWindow HelpWindow
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
   Title           =   "XMCPStudio Help"
   Type            =   0
   Visible         =   True
   Width           =   800
   Begin DesktopWKWebViewControlMBS HelpView
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
      Width           =   800
   End
End
#tag EndDesktopWindow

#tag WindowCode
	#tag Event
		Sub Resized()
		  HelpView.Width  = Me.Width
		  HelpView.Height = Me.Height
		End Sub
	#tag EndEvent

	#tag Method, Flags = &h0
		Sub LoadHelp()
		  #If DebugBuild Then
		    HelpView.developerExtrasEnabled = True
		  #EndIf
		  Var css As String = EditorHelper.LoadFiles(Array("web-assets/css/variables.css", "web-assets/help/help.css"))
		  Var js  As String = EditorHelper.LoadFiles(Array("web-assets/js/vendor/marked.min.js", "web-assets/help/help.js"))
		  Var html As String = EditorHelper.BuildEditorHTML(css, js, "")
		  HelpView.LoadHTML(html, "")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ApplyTheme(theme As String)
		  HelpView.EvaluateJavaScript(EditorHelper.ApplyThemeScript(theme))
		End Sub
	#tag EndMethod

	#tag MenuHandler
		Function FileCloseWindow() As Boolean Handles FileCloseWindow.MenuItemSelected
		  Self.Close
		  Return True
		End Function
	#tag EndMenuHandler
#tag EndWindowCode

#tag Events HelpView
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
