VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "MemoryMappedFile"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = True
'The MIT License (MIT)
'Copyright (c) 2015 Kelly Ethridge
'
'Permission is hereby granted, free of charge, to any person obtaining a copy
'of this software and associated documentation files (the "Software"), to deal
'in the Software without restriction, including without limitation the rights to
'use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
'the Software, and to permit persons to whom the Software is furnished to do so,
'subject to the following conditions:
'
'The above copyright notice and this permission notice shall be included in all
'copies or substantial portions of the Software.
'
'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
'INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
'PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
'FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
'OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
'DEALINGS IN THE SOFTWARE.
'
'
' Module: MemoryMappedFile
'

''
' Represents a simple file-to-memory mapping.
'
' @remarks Though this class is not part of .NET it is included
' to allow for easy access to mapping a file into memory.
' <p>A new <b>MemoryMappedFile</b> can be created using the <b>NewMemoryMappedFile</b>
' function.
' <pre>
'     Dim map As MemoryMappedFile
'     Set map = NewMemoryMappedFile("MyFile.txt")
' </pre>
' @see Constructors
'
Option Explicit
Implements IObject

Private Type VarTypeSafeArray1d
    VarType As Long
    SA As SafeArray1d
End Type


Private mFileName       As String
Private mFileHandle     As Long
Private mMapHandle      As Long
Private mViewHandle     As Long
Private mFileLength     As Long
Private mIsReadOnly     As Boolean
Private mView           As VarTypeSafeArray1d



''
' Returns the base address for the mapped view.
'
' @return Value of the base address.
' @remarks The BaseAddress is the starting memory location that
' the mapped file begins. Each byte in memory corrisponds to the
' same byte in the file.
'
Public Property Get BaseAddress() As Long
    Call VerifyOpen
    BaseAddress = mViewHandle
End Property

''
' Closes the currently mapped file.
'
Public Sub CloseFile()
    If IsOpen Then
        If mViewHandle <> vbNullPtr Then Call UnmapViewOfFile(mViewHandle)
        If mMapHandle <> vbNullPtr Then Call CloseHandle(mMapHandle)
        If mFileHandle <> vbNullPtr Then Call CloseHandle(mFileHandle)
        mFileHandle = vbNullPtr
    End If
End Sub

''
' Returns value indicating if the mapped file is open.
'
' @return Status of the file.
'
Public Property Get IsOpen() As Boolean
    IsOpen = (mFileHandle <> vbNullPtr)
End Property

''
' Returns if the mapped file is read-only.
'
' @return Returns True if the mapped file is opened in read-only mode, False otherwise.
' @remarks Use this property to determine if a Byte array
' returned from the <b>CreateView</b> method can be written to.
'
Public Property Get IsReadOnly() As Boolean
    IsReadOnly = mIsReadOnly
End Property

''
' Returns the filename of the currently mapped file.
'
' @return The currently mapped file.
'
Public Property Get FileName() As String
    FileName = mFileName
End Property

''
' Returns a Byte array view of the mapped file.
'
' @return A byte array pointing to the mapped file data.
' @remarks A view can be used to easily access the mapped file
' data using a Byte array as the primary access method to the data.
' <p>The byte array is locked to prevent using Erase or
' ReDim on the array, causing unknown problems.</p>
' <p><b>Warning</b><br> If the MemoryMappedFile access is read-only, then
' do not modify the byte array. The application will
' crash without write-permission.</p>
' <p>When finished with the byte array view, call DeleteView to
' unhook the array variable from the view.</p>
'
Public Function CreateView() As Byte()
    Call VerifyOpen
    
    If mView.VarType = 0 Then
        mView.VarType = vbByte
        With mView.SA
            .cbElements = 1
            .cDims = 1
            .cElements = mFileLength
            .cLocks = 1
            .fFeatures = FADF_HAVEVARTYPE Or FADF_FIXEDSIZE Or FADF_STATIC Or FADF_AUTO
            .pvData = Me.BaseAddress
        End With
    End If
    
    SAPtr(CreateView) = VarPtr(mView.SA)
End Function

''
' Unhooks a byte array view from the mapped file view.
'
' @param View A byte array view of the mapped file created from CreateView.
' @remarks This function can still be used to unhook a byte array view even
' if the MemoryMappedFile object has been closed.
' <p>If the byte array is not associated with this view then an exception is thrown.</p>
' <p>If the byte array is null then nothing happens.</p>
'
Public Sub DeleteView(ByRef View() As Byte)
    If SAPtr(View) = 0 Then Exit Sub
    
    If MemLong(SAPtrV(View) + PVDATA_OFFSET) <> mViewHandle Then _
        Throw Cor.NewArgumentException("Array is not associated with mapped file view.", "View")
    
    SAPtr(View) = 0
End Sub

''
' Returns a string representation of this object instance.
'
' @return String representing this instance.
'
Public Function ToString() As String
    ToString = MyBase.ToString(Me, App)
End Function

''
' Returns a boolean indicating if the value and this object
' instance are the same instance.
'
' @param value The value to compare equality to.
' @return Boolean indicating equality.
'
Public Function Equals(ByRef Value As Variant) As Boolean
    Equals = MyBase.Equals(Me, Value)
End Function

''
' Returns a pseudo-unique number identifying this instance.
'
' @return Pseudo-unique number identifying this instance.
'
Public Function GetHashCode() As Long
    GetHashCode = MyBase.GetHashCode(Me)
End Function


'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'   Friend Interface
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
Friend Sub Init(ByRef FileName As String, ByVal Access As FileAccess, ByVal Share As FileShare)
    If Len(FileName) = 0 Then _
        Throw Cor.NewArgumentException(Environment.GetResourceString(Argument_EmptyPath), FileName)
    If Not File.Exists(FileName) Then _
        Throw Cor.NewFileNotFoundException(, FileName)
    If FileLen(FileName) = 0 Then _
        Throw Cor.NewArgumentException("Cannot map to a zero-length file.", "FileName")
    
    ValidateFileAccess Access
    ValidateFileShare Share
    
    Dim PageAccess As Long
    Dim MapAccess As Long
    Select Case Access
        Case FileAccess.ReadAccess
            PageAccess = PAGE_READONLY
            MapAccess = FILE_MAP_READ
            mIsReadOnly = True
        Case FileAccess.WriteAccess, FileAccess.ReadWriteAccess
            PageAccess = PAGE_READWRITE
            MapAccess = FILE_MAP_ALL_ACCESS
    End Select
    
    mFileName = FileName
    mFileLength = FileLen(mFileName)

    mFileHandle = CreateFileW(FileName, Access, Share, ByVal 0&, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0)
    If mFileHandle = INVALID_HANDLE Then IOError.WinIOError Err.LastDllError, FileName
    
    mMapHandle = Api.CreateFileMapping(mFileHandle, 0, PageAccess, 0, 0, vbNullString)
    If mMapHandle = vbNullPtr Then IOError.WinIOError Err.LastDllError, FileName
    
    mViewHandle = MapViewOfFile(mMapHandle, MapAccess, 0, 0, 0)
    If mViewHandle = vbNullPtr Then IOError.WinIOError Err.LastDllError, FileName
End Sub

Private Sub VerifyOpen()
    If Not IsOpen Then Throw Cor.NewInvalidOperationException("Mapped file is closed.")
End Sub


'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'   Class Events
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
Private Sub Class_Terminate()
    If IsOpen Then Call CloseFile
End Sub


Private Sub ValidateFileAccess(ByVal Access As FileAccess)
    Select Case Access
        Case 0, FileAccess.ReadAccess, FileAccess.ReadWriteAccess, FileAccess.WriteAccess
            Exit Sub
    End Select

    Error.ArgumentOutOfRange "Access", ArgumentOutOfRange_Enum
End Sub

Private Sub ValidateFileShare(ByVal Share As FileShare)
    Select Case Share
        Case FileShare.None, FileShare.ReadShare, FileShare.ReadWriteShare, FileShare.WriteShare
            Exit Sub
    End Select
    
    Error.ArgumentOutOfRange "Share", ArgumentOutOfRange_Enum
End Sub


'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'   IObject Interface
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
Private Function IObject_Equals(Value As Variant) As Boolean
    IObject_Equals = Equals(Value)
End Function

Private Function IObject_GetHashCode() As Long
    IObject_GetHashCode = GetHashCode
End Function

Private Function IObject_ToString() As String
    IObject_ToString = ToString
End Function
