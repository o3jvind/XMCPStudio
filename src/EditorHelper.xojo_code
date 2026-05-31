#tag Module
Protected Module EditorHelper
	#tag Method, Flags = &h0
		Function LoadFiles(fileNames() As String) As String
		  Var result As String
		  For Each name As String In fileNames
		    Var f As FolderItem = App.FindFile(name)
		    If f <> Nil And f.Exists Then
		      Var ts As TextInputStream = TextInputStream.Open(f)
		      ts.Encoding = Encodings.UTF8
		      result = result + ts.ReadAll + EndOfLine
		      ts.Close
		    End If
		  Next
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function BuildEditorHTML(css As String, js As String, dataScript As String) As String
		  Var themeScript As String = "<script>var INITIAL_THEME = " + DBHelper.JSONEscape(App.CurrentTheme()) _
		    + ";(function(){var t=INITIAL_THEME;if(t==='dark'||t==='light'){document.documentElement.setAttribute('data-theme',t);}})();</script>"
		  Return "<!DOCTYPE html><html lang=""en""><head><meta charset=""UTF-8"">" _
		    + "<style>" + css + "</style></head><body>" _
		    + "<div id=""app""></div>" _
		    + themeScript _
		    + "<script>" + dataScript + "</script>" _
		    + "<script>" + js + "</script>" _
		    + "</body></html>"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ApplyThemeScript(theme As String) As String
		  Return "(function(t){if(t==='dark'||t==='light'){document.documentElement.setAttribute('data-theme',t);}else{document.documentElement.removeAttribute('data-theme');}})(" _
		    + DBHelper.JSONEscape(theme) + ");"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function UnsavedChangesDialog() As Integer
		  // Returns: 0 = Save and Close, 1 = Keep Editing, 2 = Close Anyway
		  Var dlg As New MessageDialog
		  dlg.Message = "You have unsaved changes."
		  dlg.ActionButton.Caption = "Save and Close"
		  dlg.CancelButton.Visible = True
		  dlg.CancelButton.Caption = "Keep Editing"
		  dlg.AlternateActionButton.Visible = True
		  dlg.AlternateActionButton.Caption = "Close Anyway"
		  Var btn As MessageDialogButton = dlg.ShowModal
		  If btn = dlg.ActionButton Then Return 0
		  If btn = dlg.AlternateActionButton Then Return 2
		  Return 1
		End Function
	#tag EndMethod

End Module
#tag EndModule
