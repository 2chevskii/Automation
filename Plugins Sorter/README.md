This script automatically sorts plugins in the directory it was put on (and all subdirectories).

After executing it, you will get plugins sorted in many directories with the following structure:
`sorted-plugins/<author>/<plugin name>/<version>`

**Plugin name is the class name, not the name from Info attribute!**

Plugins which script failed to analyze (no Info attribute, or it is incorrect) will be contained in the `failed-plugins/` folder.
