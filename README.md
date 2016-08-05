LODQA
=============
LODQA (Linked Open Data Question-Answering) is a system to generate SPARQL queries from natural language queries.


Dependency
----------
The Current LODQA system is dependent on two external services:

- [Enju](http://kmcs.nii.ac.jp/enju/) CGI server at [http://bionlp.dbcls.jp/enju](http://bionlp.dbcls.jp/enju).
- OntoFinder REST WS at [http://ontofinder.dbcls.jp](http://ontofinder.dbcls.jp).

Currently, LODQA is developed and tested in Ruby v2.1.1.


Using different parsers
-----------------------

Currently, LODQA supports 2 different parsers: 
* [Enju](http://kmcs.nii.ac.jp/enju/)
* [spaCy](https://spacy.io/)

By default, it will use *Enju*, but you can switch between parsers by supplying the `parser=enju` and `parser=spacy` argument to your query, respectively.

Parsers are accessed using *accessors*, which will send the query to the parsing web service, obtain the result and process the reply. The `lib/accessors/accessor.rb` is the parent class from which different accessor implementations inherit. These implementations need to implement their own `get_parse` method at least, but can also overwrite other methods to deal with peculiarities of the respective parsers. 

When a new parsing accessor is added, it needs to be registered in the `PARSERS` hash in `graphicator.rb`.

License
-------
Released under the [MIT license](http://opensource.org/licenses/MIT).

