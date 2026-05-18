def test_loader_importable():
    from functions.loader.main import load
    assert callable(load)
