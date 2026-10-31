#pragma once
#include <windows.h>

// ============================================================================
// log.h — file-backed logging for the in-game payload.
//
// WHY: r5apex_dx12.exe is a /SUBSYSTEM:WINDOWS process, so stdout/stderr go
// nowhere (there is no console attached, and AttachConsole has to hijack the
// launcher's console).  Every diagnostic the payload produced with std::cout /
// printf was therefore invisible — a Present hook could fail 100% silently and
// the operator had no evidence either way.
//
// The log is a plain append-only text file:
//     %LOCALAPPDATA%\QwenKern\<tag>_<pid>.log
// (LOCALAPPDATA is used instead of the game directory because Program Files /
//  Steam library folders are frequently not writable for the desktop user.)
//
// Cost: one fopen at init, one fprintf per line, exclusive SRW lock.  Nothing
// here touches the render thread's hot path unless the caller logs there.
// ============================================================================

// Opens the log (idempotent).  `tag` is used in the file name so a launcher run
// and a proxy-loaded run can be told apart.  Returns false if the file could
// not be created; every Logf() then becomes a no-op and the payload keeps
// running (logging must never be the reason the cheat fails).
bool LogInit(const wchar_t* tag);

// Closes the log.  Safe to call without a matching LogInit().
void LogClose();

// Absolute path of the current (or most recent) log file, or L"" if none.
const wchar_t* LogPath();

// printf-style append.  Adds a timestamp and CRLF.  Thread-safe.
void Logf(const char* format, ...);
