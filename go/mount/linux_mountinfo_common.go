// Linux mountinfo decoding is shared by Linux helper files and tests.
package mount

import "regexp"

var mountInfoEscapePattern = regexp.MustCompile(`\\([0-7]{3})`)
