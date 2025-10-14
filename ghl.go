package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"hash/crc32"
	"io"
	"os"
	"regexp"
)

const (
	ansiEscape     = "\x1b"
	ansiColorStart = "\x1b[38;5;%dm"
	ansiColorEnd   = "\x1b[0m"

	outputBufferSize = 4 * 1024
)

type BufferedOutput struct {
	buffer bytes.Buffer
	writer io.Writer
}

func NewBufferedOutput(writer io.Writer) *BufferedOutput {
	return &BufferedOutput{
		writer: writer,
	}
}

func (b *BufferedOutput) Append(content string) error {
	b.buffer.WriteString(content)
	b.buffer.WriteByte('\n')

	// Flush if we're approaching the buffer capacity
	if b.buffer.Len() >= outputBufferSize/2 {
		return b.Flush()
	}
	return nil
}

func (b *BufferedOutput) Flush() error {
	if b.buffer.Len() > 0 {
		_, err := b.writer.Write(b.buffer.Bytes())
		b.buffer.Reset()
		return err
	}
	return nil
}

func getColor(s string) uint8 {
	hash := crc32.ChecksumIEEE([]byte(s))
	return uint8(hash%200 + 16)
}

func colorizeLine(line string, regex *regexp.Regexp, grep, matchesOnly bool) (string, bool) {
	var output bytes.Buffer
	start := 0
	matches := regex.FindAllStringSubmatchIndex(line, -1)

	if len(matches) == 0 {
		if grep {
			return "", false
		}
		return line, true
	}

	for _, match := range matches {
		matchStart, matchEnd := match[0], match[1]
		matchText := line[matchStart:matchEnd]
		color := getColor(matchText)

		if !matchesOnly {
			output.WriteString(line[start:matchStart])
		}
		fmt.Fprintf(&output, ansiColorStart, color)
		output.WriteString(matchText)
		output.WriteString(ansiColorEnd)
		start = matchEnd
	}

	if !matchesOnly {
		output.WriteString(line[start:])
	}
	return output.String(), true
}

func process(reader io.Reader, writer io.Writer, regex *regexp.Regexp, grep, matchesOnly bool) error {
	bufferedOutput := NewBufferedOutput(writer)
	scanner := bufio.NewScanner(reader)

	for scanner.Scan() {
		line := scanner.Text()
		if colorized, ok := colorizeLine(line, regex, grep, matchesOnly); ok {
			if err := bufferedOutput.Append(colorized); err != nil {
				return err
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	return bufferedOutput.Flush()
}

func main() {
	var (
		help           bool
		pattern        string
		decimalNumbers bool
		words          bool
		hexNumbers     bool
		grep           bool
		matchesOnly    bool
	)

	flag.BoolVar(&help, "h", false, "Display this help and exit")
	flag.BoolVar(&help, "help", false, "Display this help and exit")
	flag.StringVar(&pattern, "p", "", "Regex pattern to highlight")
	flag.StringVar(&pattern, "pattern", "", "Regex pattern to highlight")
	flag.BoolVar(&decimalNumbers, "d", false, "Highlight decimal digits")
	flag.BoolVar(&decimalNumbers, "decimalnumbers", false, "Highlight decimal digits")
	flag.BoolVar(&words, "w", false, "Highlight (regex) words")
	flag.BoolVar(&words, "words", false, "Highlight (regex) words")
	flag.BoolVar(&hexNumbers, "x", false, "Highlight hex numbers")
	flag.BoolVar(&hexNumbers, "hexnumbers", false, "Highlight hex numbers")
	flag.BoolVar(&grep, "g", false, "Only print matching lines")
	flag.BoolVar(&grep, "grep", false, "Only print matching lines")
	flag.BoolVar(&matchesOnly, "m", false, "Only print matches")
	flag.BoolVar(&matchesOnly, "matchesonly", false, "Only print matches")

	flag.Parse()

	if help {
		flag.Usage()
		os.Exit(0)
	}

	// Determine the pattern to use
	switch {
	case pattern != "":
		// Use provided pattern
	case decimalNumbers:
		pattern = `\b\d+\b`
	case words:
		pattern = `\w+`
	case hexNumbers:
		pattern = `0x[a-fA-F0-9]{2,}|[a-fA-F0-9]{2,}`
	default:
		flag.Usage()
		os.Exit(1)
	}

	regex, err := regexp.Compile(pattern)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Cannot parse regex pattern '%s': %v\n", pattern, err)
		os.Exit(1)
	}

	if matchesOnly {
		grep = true
	}

	if err := process(os.Stdin, os.Stdout, regex, grep, matchesOnly); err != nil {
		fmt.Fprintf(os.Stderr, "Error processing input: %v\n", err)
		os.Exit(1)
	}
}
