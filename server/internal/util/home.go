package util

import (
	"log"
	"os/user"
)

// RealHomeDir returns the user's actual home directory.
// Unlike os.UserHomeDir(), this queries the system user database
// directly and is not affected by macOS sandbox $HOME overrides.
var RealHomeDir = func() string {
	u, err := user.Current()
	if err != nil {
		log.Fatalf("[UTIL] cannot determine real home directory: %v", err)
	}
	return u.HomeDir
}()
