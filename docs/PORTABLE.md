# Custom Data Directory

Vien does not ship a separate portable macOS build. You can keep its user data in a location of your choice with the `--user-data-dir` command-line option:

```sh
/Applications/Vien.app/Contents/MacOS/Vien --user-data-dir "$PWD/vien-user-data"
```

Without this option, Vien uses the standard [macOS application data directory](APPLICATION_DATA_DIRECTORY.md).
