function r = range(x, dim)
% range  Drop-in replacement for the Statistics and Machine Learning Toolbox
%        function of the same name (max minus min).
%
% WHY THIS FILE EXISTS:
%   Several LocMoFit functions call range(), which is part of MATLAB's
%   Statistics and Machine Learning Toolbox.  On installations where that
%   toolbox is not available the fitting pipeline crashes with
%   "Undefined function 'range'".  This file shadows the toolbox version
%   (or provides it when the toolbox is absent) and requires no extra
%   toolboxes.  Behaviour is identical to the original for both vectors
%   and matrices.
%
% Added locally (not part of upstream SMAP/LocMoFit) to support
% toolbox-free operation.  Safe to delete if the Statistics Toolbox is
% ever installed.
%
% Suggested git commit message:
%   "fix: add range() shim so LocMoFit runs without Statistics Toolbox"
%
% Works on vectors and matrices (column-wise by default, like the original).
if nargin < 2
    if isvector(x)
        r = max(x) - min(x);
    else
        r = max(x, [], 1) - min(x, [], 1);
    end
else
    r = max(x, [], dim) - min(x, [], dim);
end
end
