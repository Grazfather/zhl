# zhl

A simple zig port of my hl tool, inspired by Steve Losh's [colouring utility](https://stevelosh.com/blog/2021/03/small-common-lisp-cli-programs/#s8-case-study-a-batch-coloring-utility).

## Usage
```bash
zhl -p REGEXPATTERN [-g, -m]
zhl [-h,-d,-w,-x] [-g, -m]
    -h, --help             Display this help and exit.
    -p, --pattern <str>    Regex pattern to highlight
    -d, --decimalnumbers   Highlight decimal digits
    -w, --words            Highlight (regex) words
    -x, --hexnumbers       Highlight hex numbers
    -g, --grep             Only print matching lines
    -m, --matchesonly      Only print matches
```

Pipe data (e.g. log files) to it to highlight each match with a colour unique to the match.
