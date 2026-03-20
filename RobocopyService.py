import os
import sys
import time
import subprocess
import ctypes
from ctypes import wintypes

SERVICE_NAME = "RobocopyMirrorService"

def _get_base_dir() -> str:
    """
    Base directory for bundled resources.

    When packed by PyInstaller, resources are extracted/placed under sys._MEIPASS (onefile)
    or next to the executable (onedir). For normal Python run it is the folder of this file.
    """
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return sys._MEIPASS  # type: ignore[attr-defined]
    return os.path.dirname(os.path.abspath(__file__))


def _resource_path(rel_path: str) -> str:
    return os.path.join(_get_base_dir(), rel_path)


def _append_log(path: str, text: str) -> None:
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    except Exception:
        # Best-effort logging; service must not crash if logging fails
        pass


def _run_robocopy_foreground(run_bat: str, log_path: str) -> int:
    # Start the existing monitor batch (it already does monitoring + logging)
    # We keep this python process alive so it can respond to service stop.
    _append_log(log_path, f"[INFO] Starting: {run_bat}")
    proc = subprocess.Popen(
        ["cmd.exe", "/c", run_bat],
        cwd=os.path.dirname(run_bat) or None,
        creationflags=0x08000000,  # CREATE_NO_WINDOW
    )

    try:
        while True:
            if proc.poll() is not None:
                return proc.returncode
            time.sleep(1.0)
    finally:
        try:
            proc.terminate()
        except Exception:
            pass


def main():
    # If started with --run, just run in foreground (for debugging).
    if "--run" in sys.argv:
        run_bat = _resource_path("RunRobocopyMonitor.bat")
        log_path = _resource_path(os.path.join("robocopy", "Service.log"))
        if not os.path.exists(run_bat):
            raise SystemExit(f"Run script not found: {run_bat}")
        sys.exit(_run_robocopy_foreground(run_bat, log_path))

    run_bat = _resource_path("RunRobocopyMonitor.bat")
    service_log = _resource_path(os.path.join("robocopy", "Service.log"))
    if not os.path.exists(run_bat):
        raise SystemExit(f"Run script not found: {run_bat}")

    # ---------------------------
    # Windows Service implementation (ctypes, stdlib only)
    # ---------------------------
    advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    SERVICE_WIN32_OWN_PROCESS = 0x00000010
    SERVICE_ACCEPT_STOP = 0x00000001

    SERVICE_CONTROL_STOP = 0x00000001

    SERVICE_START_PENDING = 0x00000002
    SERVICE_STOP_PENDING = 0x00000003
    SERVICE_RUNNING = 0x00000004
    SERVICE_STOPPED = 0x00000001

    class SERVICE_STATUS(ctypes.Structure):
        _fields_ = [
            ("dwServiceType", wintypes.DWORD),
            ("dwCurrentState", wintypes.DWORD),
            ("dwControlsAccepted", wintypes.DWORD),
            ("dwWin32ExitCode", wintypes.DWORD),
            ("dwServiceSpecificExitCode", wintypes.DWORD),
            ("dwCheckPoint", wintypes.DWORD),
            ("dwWaitHint", wintypes.DWORD),
        ]

    SERVICE_MAIN_FUNCTION = ctypes.WINFUNCTYPE(None, wintypes.DWORD, ctypes.POINTER(wintypes.LPWSTR))
    HANDLER_FUNCTION = ctypes.WINFUNCTYPE(None, wintypes.DWORD)

    stop_event = None
    service_status_handle = None
    current_proc = None

    # Prototype: SERVICE_STATUS_HANDLE SetServiceStatus(SERVICE_STATUS_HANDLE, LPSERVICE_STATUS);
    advapi32.SetServiceStatus.argtypes = [wintypes.HANDLE, ctypes.POINTER(SERVICE_STATUS)]
    advapi32.SetServiceStatus.restype = wintypes.BOOL

    def set_status(state: int, controls_accepted: int, wait_hint: int = 0) -> None:
        status = SERVICE_STATUS()
        status.dwServiceType = SERVICE_WIN32_OWN_PROCESS
        status.dwCurrentState = state
        status.dwControlsAccepted = controls_accepted
        status.dwWin32ExitCode = 0
        status.dwServiceSpecificExitCode = 0
        status.dwCheckPoint = 0
        status.dwWaitHint = wait_hint
        if service_status_handle:
            advapi32.SetServiceStatus(service_status_handle, ctypes.byref(status))

    @HANDLER_FUNCTION
    def handler(control: int) -> None:
        # Called by SCM on STOP request
        if control == SERVICE_CONTROL_STOP and stop_event is not None:
            try:
                kernel32.SetEvent(stop_event)
            except Exception:
                pass

    @SERVICE_MAIN_FUNCTION
    def service_main(argc: int, argv) -> None:
        nonlocal stop_event, service_status_handle, current_proc

        _append_log(service_log, "[INFO] ServiceMain entered")

        # Create a manual-reset event (initially nonsignaled)
        stop_event = kernel32.CreateEventW(None, True, False, None)
        if not stop_event:
            _append_log(service_log, "[ERROR] CreateEventW failed")
            return

        # Register control handler
        handler_ptr = handler
        advapi32.RegisterServiceCtrlHandlerW.argtypes = [wintypes.LPCWSTR, HANDLER_FUNCTION]
        advapi32.RegisterServiceCtrlHandlerW.restype = wintypes.HANDLE
        service_status_handle = advapi32.RegisterServiceCtrlHandlerW(SERVICE_NAME, handler_ptr)
        if not service_status_handle:
            _append_log(service_log, "[ERROR] RegisterServiceCtrlHandlerW failed")
            return

        set_status(SERVICE_START_PENDING, 0, wait_hint=3000)

        # Start the batch process
        try:
            _append_log(service_log, f"[INFO] Starting batch: {run_bat}")
            current_proc = subprocess.Popen(
                ["cmd.exe", "/c", run_bat],
                cwd=os.path.dirname(run_bat) or None,
                creationflags=0x08000000,  # CREATE_NO_WINDOW
            )
        except Exception as e:
            _append_log(service_log, f"[ERROR] Failed to start batch: {e}")
            set_status(SERVICE_STOPPED, 0, wait_hint=0)
            return

        set_status(SERVICE_RUNNING, SERVICE_ACCEPT_STOP, wait_hint=0)

        # Wait until stop is requested or robocopy exits unexpectedly
        WAIT_INTERVAL_MS = 1000
        while True:
            # Check stop event
            res = kernel32.WaitForSingleObject(stop_event, WAIT_INTERVAL_MS)
            stopped = (res == 0x00000000)  # WAIT_OBJECT_0
            if stopped:
                break

            if current_proc is not None and current_proc.poll() is not None:
                # Robocopy process ended - treat it as stopped
                _append_log(service_log, "[WARN] Batch process exited unexpectedly")
                break

        # Stop pending
        set_status(SERVICE_STOP_PENDING, 0, wait_hint=5000)
        _append_log(service_log, "[INFO] Stopping batch process")
        try:
            if current_proc is not None:
                current_proc.terminate()
                try:
                    current_proc.wait(timeout=10)
                except Exception:
                    current_proc.kill()
        except Exception:
            pass

        try:
            if stop_event is not None:
                kernel32.CloseHandle(stop_event)
        except Exception:
            pass

        set_status(SERVICE_STOPPED, 0, wait_hint=0)
        _append_log(service_log, "[INFO] Service stopped")

    class SERVICE_TABLE_ENTRY(ctypes.Structure):
        # According to WinAPI: lpServiceProc is a pointer to a SERVICE_MAIN_FUNCTIONW.
        _fields_ = [("lpServiceName", wintypes.LPWSTR), ("lpServiceProc", ctypes.c_void_p)]

    # Start service control dispatcher
    advapi32.StartServiceCtrlDispatcherW.argtypes = [ctypes.POINTER(SERVICE_TABLE_ENTRY)]
    advapi32.StartServiceCtrlDispatcherW.restype = wintypes.BOOL

    dispatch = (SERVICE_TABLE_ENTRY * 2)()
    dispatch[0].lpServiceName = SERVICE_NAME
    dispatch[0].lpServiceProc = ctypes.cast(service_main, ctypes.c_void_p)
    dispatch[1].lpServiceName = None
    dispatch[1].lpServiceProc = None

    _append_log(service_log, "[INFO] Starting StartServiceCtrlDispatcherW")
    ok = advapi32.StartServiceCtrlDispatcherW(dispatch)
    if not ok:
        # If called outside of SCM context, this will typically fail.
        err = ctypes.get_last_error()
        _append_log(service_log, f"[ERROR] StartServiceCtrlDispatcherW failed, error={err}")
        # Do not raise to avoid crashing the service host


if __name__ == "__main__":
    main()

