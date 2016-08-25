Diff2PO
=======

Simple script which can be used for generation list of untranslated strings.

Script takes diff file between 2 branches, finds all text strings into the code
and checks if those strings already have a translation into the DB.

As a result it generates PO file.

**Usage:**

    diff2po [-db|--dbcheck] [-dbro|--dbro]
               [-dbu|--dbuser user] [-dbp|--dbpass pass]
               [-dbn|--dbname name]
               [-dbh|--dbhost host[=localhost]] [-dbpr|--dbport port[=3306]]
               [-h|--help] INPUT_FILE

It may work with usual _stdin_ flow.

PO file is generated into _stout_ flow.

If you need to check translation strings in the DB(mysql) use -db param and set access credentials.
If your DB works in read-only mode use -dbro parameter.

_test.diff_ may be used for testing purposes.
