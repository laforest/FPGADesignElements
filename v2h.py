#! /usr/bin/python3

"""
This program converts Verilog code to a basic webpage: lines that *begin*
with a line comment ("// ..."), or groups of such lines separated by blank
lines, get put together as a block of text and processed as Markdown text. The
remaining non-blank, non-line-comment lines are code, which gets wrapped in a <pre>
block.

Thus you can keep the Verilog code, its documentation, and its presentation in sync.

Copyright 2019 Charles Eric LaForest
License: https://opensource.org/licenses/MIT

"""

import markdown
import sys


# Web page header and footer, with a placeholder for the page title.

header = """
<html>
<head>
<link rel="shortcut icon" href="./favicon.ico">
<link rel="stylesheet" type="text/css" href="./style.css">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{0}</title>
</head>
<body>
"""

footer = """
<hr><a href="http://fpgacpu.ca/">fpgacpu.ca</a>
</body>
</html>
"""

def clean_filename(filename):
    """Convert the Verilog filename into the web page title.
       Simple stripping to catch '.v' and '.vh' extensions."""
    return filename.rstrip(".vh").replace("_", " ")

def is_comment(line):
    return line.lstrip().startswith("//")

def is_blank(line):
    """If a line is only spaces or tabs and a return, it's blank."""
    return line.strip(" \t") == "\n"

def is_eof(line):
    """readline only ever returns an empty line at EOF"""
    return line == ""

def process_comments(line, f):
    """Take in comment/blank lines until a line is neither.
       Then process them as Markdown and output the XHTML."""
    comment_block = ""
    while (is_comment(line) or is_blank(line)) and not is_eof(line):
        comment_block = comment_block + line.lstrip("/ ")
        line = f.readline()
    html = markdown.markdown(comment_block)
    print(html)
    print()
    return line

def process_code(line, f):
    """Take in code lines until a line is a comment.
       Then remove the previous line if it's blank.
       Then wrap the code in a <pre> block."""
    code_block = []
    while not is_comment(line) and not is_eof(line):
        code_block.append(line)
        line = f.readline()
    if is_blank(code_block[-1]):
        code_block.pop()
    print("<pre>")
    for code_line in code_block:
        print(code_line, end="")
    print("</pre>\n")
    return line

if __name__ == "__main__":
    filename = sys.argv[1]
    f = open(filename, 'r')
    filename = clean_filename(filename)
    print(header.format(filename))
    line = f.readline()
    # Note the returning of the last line read and restarting of parsing.
    # This avoids the need for look-ahead to know when to end a comment or code block.
    while not is_eof(line):
        if is_comment(line):
            line = process_comments(line, f)
            continue
        if not is_comment(line) and not is_blank(line):
            line = process_code(line, f)
            continue
        line = f.readline()
    print(footer)
    f.close()

