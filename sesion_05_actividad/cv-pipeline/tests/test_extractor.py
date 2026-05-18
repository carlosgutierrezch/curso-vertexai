def test_extractor_importable():
    from functions.extractor.main import extract
    assert callable(extract)
