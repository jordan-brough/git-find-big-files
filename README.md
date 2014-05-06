```
Synopsis: Searches the entire history of a git repository for large files and determines their current in-use status.

Usage: big-file-finder.rb [options]

Options:
    -t, --threshold=THRESHOLD        File size threshold in MB.
                                      Default: 1.0 MB.
    -r, --refs=REFS                  A comma-separated list of refs to consider when determining in-use/not-in-use status.
                                      Passing the special string '-all' like: '--refs=-all' will use all refs in git/refs.
                                      Default: HEAD.
    -k, --kind=in-use|not-in-use|all Which kind of files to show.
                                      An 'in-use' file is one that is currently being referenced by the head of one of the refs from the 'refs' option.
                                      Default: 'not-in-use'.
    -f, --format=FORMAT              Output format string, with ruby style string interpolation.
                                      Available placeholders: sha, path, size, refs, kind.
                                      Use bash escaping to pass special characters, e.g.: --format=$'%{path}\t%{size}
                                      Default: $'%{sha}\t%{kind}\t%{size}\t%{path}'
        --[no-]output-refs           Add a column that lists the refs that currently reference each path.
                                      Note: This can be a large list depending on your repository.
    -z, --[no-]null                  \0 line termination on output.
    -h, --help                       Show this message
        --version                    Show version
```