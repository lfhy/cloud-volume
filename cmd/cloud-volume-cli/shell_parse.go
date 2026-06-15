// Shell parsing helpers are shared by execution and completion paths.
package main

import "strings"

func splitShellLine(line string) ([]string, error) {
	args, _, err := splitShellLineWithState(line)
	return args, err
}

func splitShellLineWithState(line string) ([]string, bool, error) {
	args := make([]string, 0)
	current := strings.Builder{}
	inQuote := byte(0)
	escaped := false

	flush := func() {
		if current.Len() == 0 {
			return
		}
		args = append(args, current.String())
		current.Reset()
	}

	for index := 0; index < len(line); index++ {
		ch := line[index]
		switch {
		case escaped:
			current.WriteByte(ch)
			escaped = false
		case ch == '\\':
			escaped = true
		case inQuote != 0:
			if ch == inQuote {
				inQuote = 0
				continue
			}
			current.WriteByte(ch)
		case ch == '\'' || ch == '"':
			inQuote = ch
		case ch == ' ' || ch == '\t':
			flush()
		default:
			current.WriteByte(ch)
		}
	}
	if escaped {
		current.WriteByte('\\')
	}
	if inQuote != 0 {
		return nil, false, errUnterminatedQuote(inQuote)
	}
	trailingSpace := len(line) > 0 && (line[len(line)-1] == ' ' || line[len(line)-1] == '\t')
	flush()
	return args, trailingSpace, nil
}

func errUnterminatedQuote(quote byte) error {
	return shellParseError{quote: quote}
}

type shellParseError struct {
	quote byte
}

func (e shellParseError) Error() string {
	return "unterminated quote " + `"` + string(e.quote) + `"`
}
