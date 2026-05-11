//go:build windows

package main

import (
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

func isProcessAlive(proc *os.Process) bool {
	// On Windows, Signal(0) is not supported; query the exit code instead.
	h, err := syscall.OpenProcess(syscall.PROCESS_QUERY_INFORMATION, false, uint32(proc.Pid))
	if err != nil {
		return false
	}
	defer syscall.CloseHandle(h)
	var code uint32
	if err := syscall.GetExitCodeProcess(h, &code); err != nil {
		return false
	}
	return code == 259 // STILL_ACTIVE
}

func terminateProcess(proc *os.Process) error {
	// Windows has no SIGTERM; Kill() calls TerminateProcess.
	return proc.Kill()
}

func setDaemonProcess(cmd *exec.Cmd) {
	// CREATE_NO_WINDOW prevents a console window from appearing.
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: 0x08000000, // CREATE_NO_WINDOW
	}
}

func registerShutdownSignals(ch chan os.Signal) {
	signal.Notify(ch, os.Interrupt)
}
