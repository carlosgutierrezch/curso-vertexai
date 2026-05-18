def test_validator_importable():
    from functions.validator.main import validate
    assert callable(validate)
