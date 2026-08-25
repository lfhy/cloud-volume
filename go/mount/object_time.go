// Object timestamp helpers preserve the client-local ObjectInfo wire contract.
package mount

import "time"

const objectLastModifiedLayout = "2006-01-02 15:04:05"

func parseObjectLastModified(value string) (time.Time, error) {
	return time.ParseInLocation(objectLastModifiedLayout, value, time.Local)
}
