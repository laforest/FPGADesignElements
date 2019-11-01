#! /usr/bin/python3

"""
This program converts Verilog code to a basic webpage: lines that *begin*
with a line comment ("// ..."), or groups of such lines separated by blank
lines, get put together as a block of text and processed as Markdown text. The
remaining non-blank, non-line-comment lines are code, which gets wrapped in a <pre>
block.

Thus you can keep the Verilog code, its documentation, and its presentation in sync.

A file is only updated if the newly generated HTML is not identical to the existing HTML file.

Copyright (c) 2019 Charles Eric LaForest
License: https://opensource.org/licenses/MIT
"""

import markdown
import sys

# Web page header and footer, with a placeholder for the page title.

header = """<html>
<head>
<link rel="shortcut icon" href="./favicon.ico">
<link rel="stylesheet" type="text/css" href="./style.css">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{0}</title>
</head>
<body>

<p><a href="./{1}">Source</a></p>

"""

footer = """<hr><a href="./index.html">back to FPGA Design Elements</a>
</body>
</html>

"""

def base_filename(filename):
    """Strip Verilog filename extension"""
    return filename.rstrip(".vh")

def output_filename(filename):
    """Convert input Verilog filename to output HTML filename"""
    return base_filename(filename) + ".html"

def filename_to_title(filename):
    """Convert the Verilog filename into the web page title"""
    return base_filename(filename).replace("_", " ")

def is_comment(line):
    return line.startswith("//")

def is_blank(line):
    """If a line is only spaces or tabs and a return, it's blank."""
    return line.strip(" \t") == "\n"

def is_eof(line):
    """readline only ever returns an empty line at EOF"""
    return line == ""

def process_comments(line, processed_contents, f):
    """Take in comment/blank lines until a line is neither.
       Then process them as Markdown and output the XHTML."""
    comment_block = ""
    while (is_comment(line) or is_blank(line)) and not is_eof(line):
        comment_block = comment_block + line.lstrip("/ ")
        line = f.readline()
    html = markdown.markdown(comment_block)
    processed_contents += html + "\n\n"
    return line, processed_contents

def process_code(line, processed_contents, f):
    """Take in code lines until a line is a comment.
       Then remove the previous line if it's blank.
       Then wrap the code in a <pre> block."""
    code_block = []
    while not is_comment(line) and not is_eof(line):
        code_block.append(line)
        line = f.readline()
    if is_blank(code_block[-1]):
        code_block.pop()
    processed_contents += "<pre>\n"
    for code_line in code_block:
        processed_contents += code_line
    processed_contents += "</pre>\n\n"
    return line, processed_contents

if __name__ == "__main__":
    verilog_filename = sys.argv[1]
    html_filename = output_filename(verilog_filename)

    try:
        f = open(html_filename, 'r')
        existing_file_contents = f.read()
        f.close()
    except OSError:
        existing_file_contents = ""
        pass

    f = open(verilog_filename, 'r')
    processed_contents = ""
    title = filename_to_title(verilog_filename)
    processed_contents += header.format(title, verilog_filename)
    line = f.readline()
    # Note the returning of the last line read and restarting of parsing.
    # This avoids the need for look-ahead to know when to end a comment or code block.
    while not is_eof(line):
        if is_comment(line):
            line, processed_contents = process_comments(line, processed_contents, f)
            continue
        if not is_comment(line) and not is_blank(line):
            line, processed_contents = process_code(line, processed_contents, f)
            continue
        line = f.readline()
    processed_contents += footer
    f.close()

    if processed_contents != existing_file_contents:
        print("Updating {0}".format(html_filename));
        f = open(html_filename, 'w')
        f.write(processed_contents)
        f.close()
    else:
        print("Skipping {0}".format(html_filename));

    print("Done.")

