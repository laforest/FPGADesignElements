# FPGA Design Elements

## Copyright (c) 2019-2020 Charles Eric LaForest, PhD.

A self-contained online book containing a library of FPGA design elements and
related coding/design guides.

You can read it online at http://fpgacpu.ca/fpga/

To obtain your own local copy:
```
git clone https://github.com/laforest/FPGADesignElements.git
```
then access [index.html](./index.html) from your favourite browser.

All files are in one directory, so you can use it as a library in your CAD
tools by simply importing all Verilog files.

**IMPORTANT:** The module definitions are, by design, not usable as-is.
Unless the design requires some minimum or constant value, all module
parameters have a default value of 0 or an empty string. This is intentional,
so when a user forgets to set a parameter when instantiating a module,
synthesis will (almost always) fail, and linting also. Putting usable default
values in the module definitions might not get noticed and cause bugs. This
means the modules are not synthesizable as defined, but must be instantiated
separately to set the parameters, which is what one normally does anyway.

See [LICENSE](./LICENSE) for the details, but overall, you are free to use this
book as you please.

Contributions are welcome. Please email <a href="mailto:eric@fpgacpu.ca?subject=FPGA%20Design%20Elements">eric@fpgacpu.ca</a>
or Twitter <a href="https://twitter.com/elaforest">@elaforest</a> or join the <a href="https://discordapp.com/invite/bWBdwVD">Discord server</a>.

