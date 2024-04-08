# zoogle
A search tool for browsing a codebase via a function signiture

## Build

```shell
> zig build
```
## Usage

Running with example signiture:
```shell
> zig build run -- "_(node, node) bool"
```
Running with example signiture if binary is in $PATH:
```shell
> zoogle "_(node, node) bool"
```
