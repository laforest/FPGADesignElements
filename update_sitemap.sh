#! /bin/bash

find . -type f -name "*.html" | sed -e 's#./#http://fpgacpu.ca/fpga/#' | sort > sitemap.txt

