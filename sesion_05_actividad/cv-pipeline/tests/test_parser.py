def test_parser_importable():
    from functions.parser.main import parse
    assert callable(parse)
