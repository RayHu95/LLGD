function runLocalVerificationGeometry
    revisionRoot = fileparts(mfilename('fullpath'));
    addpath(revisionRoot);
    outputRoot = fullfile(revisionRoot, 'results', 'local_verification_geometry');
    runRTComparisonLLGD(1:3, false, outputRoot);
end
