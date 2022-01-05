#!/usr/bin/env python3
import os
from collections import OrderedDict

# Load var from environment if present
def LoadEnv(var, default=""):
    if (var in os.environ):
        return os.environ[var]
    else:
        return default

# Get file absolute path
def AbsPath(p):
    return os.path.abspath(p)


def PrependPaths(paths, prefix):
    r = []
    # make OrderedDict to remove duplicates preserving order
    d = OrderedDict.fromkeys(paths)
    for p in d:
        r.append(prefix + "/" + p)
    return r
    
def TechDir(p):
    return "tech/"+p.TARGET_TECHNOLOGY.lower()
