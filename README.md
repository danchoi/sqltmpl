# sqltmpl

Templates arguments and STDIN into a SQL template.


## Synopsis

```bash
$ sqltmpl -t 'INSERT into fruits (name, price) VALUES ($1, $2:num);' apple 1.99

# result:

INSERT into fruits (name, price) VALUES ('apple', 1.99);
```

```bash
$ echo -n apple | 
  sqltmpl -t 'INSERT into fruits (name, price) VALUES ($STDIN, $1:num);' 1.99

# result:

INSERT into fruits (name, price) VALUES ('apple', 1.99);
```


WARNING: Use single quotes around the SQL template expression so that
Bash does not do interpolation.

'null' text is translated into NULL:

The subtitution placeholders are thus:

    $1      # value is a string; the value is quoted and escaped
    $2:num  # value is a number; not quoted
    $3:bool # value is a bool; "t" is true, "f" is false
    $STDIN  # value is a string, and includes all the text from STDIN,
              quoted and escaped

The placeholders start counting from position 1, not zero.

## TODO

* Be more liberal in what translates to boolean and null. 
