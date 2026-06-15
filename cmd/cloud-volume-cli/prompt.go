// Interactive prompts are isolated here so init stays focused on config flow.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"golang.org/x/term"
)

type promptUI struct {
	reader *bufio.Reader
	out    io.Writer
}

func newPromptUI() *promptUI {
	return &promptUI{
		reader: bufio.NewReader(os.Stdin),
		out:    os.Stdout,
	}
}

func (ui *promptUI) askString(label, defaultValue string, required bool) (string, error) {
	for {
		if defaultValue != "" {
			fmt.Fprintf(ui.out, "%s [%s]: ", label, defaultValue)
		} else {
			fmt.Fprintf(ui.out, "%s: ", label)
		}
		line, err := ui.reader.ReadString('\n')
		if err != nil {
			return "", err
		}
		value := strings.TrimSpace(line)
		if value == "" {
			value = strings.TrimSpace(defaultValue)
		}
		if required && value == "" {
			fmt.Fprintln(ui.out, "该项必填，请重新输入。")
			continue
		}
		return value, nil
	}
}

func (ui *promptUI) askBool(label string, defaultValue bool) (bool, error) {
	suffix := "y/N"
	if defaultValue {
		suffix = "Y/n"
	}
	for {
		fmt.Fprintf(ui.out, "%s [%s]: ", label, suffix)
		line, err := ui.reader.ReadString('\n')
		if err != nil {
			return false, err
		}
		value := strings.ToLower(strings.TrimSpace(line))
		switch value {
		case "":
			return defaultValue, nil
		case "y", "yes":
			return true, nil
		case "n", "no":
			return false, nil
		default:
			fmt.Fprintln(ui.out, "请输入 y 或 n。")
		}
	}
}

func (ui *promptUI) askSecret(label string, currentValue string) (string, error) {
	if term.IsTerminal(int(os.Stdin.Fd())) {
		prompt := fmt.Sprintf("%s", label)
		if strings.TrimSpace(currentValue) != "" {
			prompt += " [保留现有值请直接回车]"
		}
		fmt.Fprintf(ui.out, "%s: ", prompt)
		secret, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(ui.out)
		if err != nil {
			return "", err
		}
		value := strings.TrimSpace(string(secret))
		if value == "" && strings.TrimSpace(currentValue) != "" {
			return strings.TrimSpace(currentValue), nil
		}
		if value == "" {
			fmt.Fprintln(ui.out, "该项必填，请重新输入。")
			return ui.askSecret(label, currentValue)
		}
		return value, nil
	}
	return ui.askString(label, currentValue, true)
}

func (ui *promptUI) askChoice(label string, options []string, currentValue string) (string, error) {
	if len(options) == 0 {
		return "", nil
	}
	if term.IsTerminal(int(os.Stdin.Fd())) {
		return ui.askChoiceWithArrows(label, options, currentValue)
	}
	return ui.askChoiceByNumber(label, options, currentValue)
}

func (ui *promptUI) askOptionalChoice(label string, options []string, currentValue string) (string, error) {
	withSkip := append([]string{"(暂不设置默认 Bucket)"}, options...)
	selected := currentValue
	if strings.TrimSpace(selected) == "" {
		selected = withSkip[0]
	}
	choice, err := ui.askChoice(label, withSkip, selected)
	if err != nil {
		return "", err
	}
	if choice == withSkip[0] {
		return "", nil
	}
	return choice, nil
}

func (ui *promptUI) askChoiceByNumber(label string, options []string, currentValue string) (string, error) {
	selected := 0
	for index, option := range options {
		if strings.TrimSpace(option) == strings.TrimSpace(currentValue) {
			selected = index
			break
		}
	}
	fmt.Fprintf(ui.out, "%s:\n", label)
	for index, option := range options {
		marker := " "
		if index == selected {
			marker = "*"
		}
		fmt.Fprintf(ui.out, "  %s %d. %s\n", marker, index+1, option)
	}

	for {
		fmt.Fprintf(ui.out, "请选择 bucket [默认 %d]: ", selected+1)
		line, err := ui.reader.ReadString('\n')
		if err != nil {
			return "", err
		}
		value := strings.TrimSpace(line)
		if value == "" {
			return options[selected], nil
		}
		choice, err := strconv.Atoi(value)
		if err != nil || choice < 1 || choice > len(options) {
			fmt.Fprintln(ui.out, "请输入有效序号。")
			continue
		}
		return options[choice-1], nil
	}
}

func (ui *promptUI) askChoiceWithArrows(label string, options []string, currentValue string) (string, error) {
	selected := 0
	for index, option := range options {
		if strings.TrimSpace(option) == strings.TrimSpace(currentValue) {
			selected = index
			break
		}
	}

	fd := int(os.Stdin.Fd())
	oldState, err := term.MakeRaw(fd)
	if err != nil {
		return "", err
	}
	defer func() {
		_ = term.Restore(fd, oldState)
	}()

	reader := bufio.NewReader(os.Stdin)
	render := func() {
		fmt.Fprintf(ui.out, "\r%s: 使用上下键选择，回车确认\r\n", label)
		for index, option := range options {
			prefix := "  "
			if index == selected {
				prefix = "> "
			}
			fmt.Fprintf(ui.out, "%s%s\r\n", prefix, option)
		}
		fmt.Fprintf(ui.out, "\x1b[%dA", len(options)+1)
	}

	clear := func() {
		for range len(options) + 1 {
			fmt.Fprint(ui.out, "\r\x1b[2K\x1b[1B")
		}
		fmt.Fprintf(ui.out, "\x1b[%dA\r", len(options)+1)
	}

	render()
	for {
		key, err := reader.ReadByte()
		if err != nil {
			clear()
			return "", err
		}
		switch key {
		case '\r', '\n':
			clear()
			fmt.Fprintf(ui.out, "%s: %s\r\n", label, options[selected])
			return options[selected], nil
		case 3:
			clear()
			return "", fmt.Errorf("prompt aborted")
		case 27:
			next, err := reader.ReadByte()
			if err != nil {
				clear()
				return "", err
			}
			if next != '[' {
				continue
			}
			direction, err := reader.ReadByte()
			if err != nil {
				clear()
				return "", err
			}
			switch direction {
			case 'A':
				if selected > 0 {
					selected--
				}
			case 'B':
				if selected < len(options)-1 {
					selected++
				}
			default:
				continue
			}
			clear()
			render()
		}
	}
}
