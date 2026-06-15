// Object time helpers normalize remote timestamps before they reach the UI layer.
package s3

import "time"

const objectTimeLayout = "2006-01-02 15:04:05"

func formatObjectLastModified(value *time.Time) string {
	if value == nil {
		return ""
	}
	return value.In(time.Local).Format(objectTimeLayout)
}
