"""Shared helpers: load the extension-less scripts in overlay/ as modules."""
import importlib.machinery
import importlib.util
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def script(*parts):
    return os.path.join(ROOT, "overlay", *parts)


def load(name, *parts):
    loader = importlib.machinery.SourceFileLoader(name, script(*parts))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def elf(bits, machine):
    """An ELF header: ident (16 bytes), e_type (2), e_machine (2), padding."""
    return b"\x7fELF" + bytes([bits, 1, 1]) + b"\x00" * 9 + (2).to_bytes(2, "little") + machine.to_bytes(2, "little") + b"\x00" * 40


ELF_X86_64 = elf(2, 62)
ELF_I386 = elf(1, 3)
ELF_ARM64 = elf(2, 183)
