#! /usr/bin/python3

"""
Reads in a file which defines a Verilog module and outputs a ready-to-populate
instantiation of that module. **This is a hack, not a real parser!** This
script only works with the fixed module definition style of the FPGA Design
Elements. For example, parameter and port block delimiters, such as "#(" and ")",
MUST be on their own lines.

When your code is very modular, instantiating the modules becomes a large
fraction of writing new code. This script automates 99% of the work of
converting a module definition header into a module instance.  You'll have to
align columns and remove any comments you don't want to keep as notes.

Simply call the script with the file name containing the module you want to
use, and pipe the output into your text editor. The instance is indented one
tabstop as that's the needed indentation almost always.

Copyright (c) 2020 Charles Eric LaForest
License: https://opensource.org/licenses/MIT
"""

import sys

# Spaces per indent level

tabstop = 4

# Some line test functions. Makes writing later code easier.

def is_comment(line):
    return line.strip().startswith("//")

def is_blank(line):
    """If a line is only spaces or tabs and a return, it's blank."""
    return line.strip(" \t") == "\n"

def is_eof(line):
    """readline only ever returns an empty line at EOF"""
    return line == ""

def is_name(line):
    return line.strip().startswith("module")

def is_parameter(line):
    return line.strip().startswith("parameter")

def is_port(line):
    line = line.strip()
    return line.startswith("input") or line.startswith("output") or line.startswith("inout")

# We read the file line by line, in a forward only manner.
# Each sub-loop eats input and appends its output until it is done.
# Each sub-loop always finishes by reading in one line to prime the next loop.
# When we reach the end of the module definition header, we are done.
# The rest of the file is never read.

if __name__ == "__main__":
    filename    = sys.argv[1]
    raw_file    = open(filename)

    instance = []

    # Skip over comments until the code
    line = raw_file.readline()
    while not is_eof(line):
        if is_comment(line) or is_blank(line):
            line = raw_file.readline()
            continue
        else:
            break

    # Module name
    while not is_eof(line):
        if is_name(line):
            line = line.strip().split()
            name = line[-1]
            name = "\t{}".format(name)
            instance.append(name)
            line = raw_file.readline()
            break
        else:
            line = raw_file.readline()
            continue

    # Skip the parameter template section if there are no parameters
    # This assumes the parameters begin IMMEDIATELY with a "#(" line
    # Else there must be NO text before the instance name

    if line.strip().startswith("#("):
        # Begin parameter block
        instance.append("\t#(")

        # Module parameters
        # With special case to handle trailing comments (often used as notes)
        while not is_eof(line):
            if line.strip().startswith(")"):
                break
            if is_comment(line) or is_blank(line):
                instance.append("\t\t{}".format(line.strip()))
                line = raw_file.readline()
                continue
            if is_parameter(line):
                line = line.strip().split()
                comment_pos = 0
                comment = ""
                if "//" in line:
                    comment_pos = line.index("//")
                    comment = " ".join(line[comment_pos:])
                equals_index = line.index("=")
                parameter = line[equals_index-1]
                # Does the parameter have a comma at the end?
                if line[equals_index+1][-1] == ",":
                    parameter = "\t\t.{}\t(),".format(parameter)
                else:
                    parameter = "\t\t.{}\t()".format(parameter)
                if comment_pos != 0:
                    parameter = parameter + "\t{}".format(comment)
                instance.append(parameter)
                line = raw_file.readline()
                continue
            else:
                line = raw_file.readline()
                continue

        # End parameter block
        instance.append("\t)")

    # Put instance name placeholder, and start port block
    instance.append("\tinstance_name\n\t(")

    # Module ports
    # With special case to handle trailing comments (often used as notes)
    while not is_eof(line):
        if line.strip().startswith(");"):
            break
        if is_comment(line) or is_blank(line):
            instance.append("\t\t{}".format(line.strip()))
            line = raw_file.readline()
            continue
        if is_port(line):
            line = line.strip().split()
            comment_pos = 0
            comment = ""
            if "//" in line:
                comment_pos = line.index("//")
                comment = " ".join(line[comment_pos:])
            port = line[comment_pos-1]
            # Does the port have a comma at the end?
            port_bare = port.strip(",")
            if port[-1] == ",":
                port = "\t\t.{}\t(),".format(port_bare)
            else:
                port = "\t\t.{}\t()".format(port_bare)
            if comment_pos != 0:
                port = port + "\t{}".format(comment)
            instance.append(port)
            line = raw_file.readline()
            continue
        else:
            line = raw_file.readline()
            continue

    # End port block, which ends the module instance
    instance.append("\t);")

    # No need to read more from the file
    raw_file.close()

    # Convert tabs to spaces and print
    # Except for blank lines (just delete the tabs instead)
    # There are no "\n" at this point (it's a list of strings)
    # FIXME: we could do some work here to line things up dynamically.
    for line in instance:
        if line.lstrip("\t") == "":
            line = ""
        else:
            line = line.expandtabs(tabstop)
        print(line)

