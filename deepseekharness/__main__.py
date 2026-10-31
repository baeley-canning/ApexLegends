import sys

if not __package__:
    # Run as `python path/to/deepseekharness ...` or `python path/to/__main__.py ...`
    import pathlib
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
    from deepseekharness.cli import main
else:
    from .cli import main

sys.exit(main())
