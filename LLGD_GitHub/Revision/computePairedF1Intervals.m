function results = computePairedF1Intervals(detailInput, outputFile)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    defaultInput = fullfile(codeRoot, 'Revision', 'results', ...
        'comparison_four_detail.csv');
    defaultOutput = fullfile(codeRoot, 'Revision', 'results', ...
        'comparison_four_paired_f1.csv');

    if nargin < 1 || isempty(detailInput)
        detailInput = defaultInput;
    end
    if istable(detailInput)
        detail = detailInput;
        if nargin < 2 || isempty(outputFile)
            outputFile = defaultOutput;
        end
    elseif ischar(detailInput) || isstring(detailInput)
        inputFile = char(detailInput);
        detail = readtable(inputFile);
        if nargin < 2 || isempty(outputFile)
            inputFolder = fileparts(inputFile);
            if isempty(inputFolder)
                inputFolder = pwd;
            end
            outputFile = fullfile(inputFolder, 'comparison_four_paired_f1.csv');
        end
    else
        error('Input must be a table or a CSV file.');
    end

    requiredNames = {'Dataset', 'Packet', 'Method', 'F1'};
    if ~all(ismember(requiredNames, detail.Properties.VariableNames))
        error('The detail table must contain Dataset, Packet, Method, and F1.');
    end

    datasetValues = string(detail.Dataset);
    methodValues = string(detail.Method);
    packetValues = double(detail.Packet);
    f1Values = double(detail.F1);
    datasets = unique(datasetValues, 'stable');
    methods = unique(methodValues, 'stable');
    methods(methods == "LLGD") = [];

    rowNum = numel(datasets) * numel(methods);
    datasetOut = strings(rowNum, 1);
    methodOut = strings(rowNum, 1);
    pairedN = zeros(rowNum, 1);
    llgdMean = nan(rowNum, 1);
    methodMean = nan(rowNum, 1);
    meanDifference = nan(rowNum, 1);
    ciLower = nan(rowNum, 1);
    ciUpper = nan(rowNum, 1);
    llgdWins = zeros(rowNum, 1);

    rng(2025, 'twister');
    bootstrapNum = 10000;
    row = 0;
    for datasetIdx = 1:numel(datasets)
        datasetName = datasets(datasetIdx);
        llgdMask = datasetValues == datasetName & methodValues == "LLGD";
        llgdPackets = packetValues(llgdMask);
        llgdF1 = f1Values(llgdMask);

        for methodIdx = 1:numel(methods)
            row = row + 1;
            methodName = methods(methodIdx);
            methodMask = datasetValues == datasetName & methodValues == methodName;
            currentPackets = packetValues(methodMask);
            currentF1 = f1Values(methodMask);
            if numel(unique(llgdPackets)) ~= numel(llgdPackets) || ...
                    numel(unique(currentPackets)) ~= numel(currentPackets)
                error('Each method must have at most one row per packet.');
            end

            [~, llgdIdx, methodPairIdx] = intersect( ...
                llgdPackets, currentPackets, 'stable');
            llgdPair = llgdF1(llgdIdx);
            methodPair = currentF1(methodPairIdx);
            valid = isfinite(llgdPair) & isfinite(methodPair);
            llgdPair = llgdPair(valid);
            methodPair = methodPair(valid);
            difference = llgdPair - methodPair;
            n = numel(difference);

            datasetOut(row) = datasetName;
            methodOut(row) = methodName;
            pairedN(row) = n;
            if n == 0
                continue;
            end

            llgdMean(row) = mean(llgdPair);
            methodMean(row) = mean(methodPair);
            meanDifference(row) = mean(difference);
            llgdWins(row) = sum(difference > 0);

            % Resample paired packet differences.
            sampleIdx = randi(n, n, bootstrapNum);
            bootstrapMeans = sort(mean(difference(sampleIdx), 1));
            lowerIdx = max(1, ceil(0.025 * bootstrapNum));
            upperIdx = min(bootstrapNum, ceil(0.975 * bootstrapNum));
            ciLower(row) = bootstrapMeans(lowerIdx);
            ciUpper(row) = bootstrapMeans(upperIdx);
        end
    end

    results = table(datasetOut, methodOut, pairedN, llgdMean, methodMean, ...
        meanDifference, ciLower, ciUpper, llgdWins, 'VariableNames', ...
        {'Dataset', 'Method', 'N', 'LLGDMeanF1', 'MethodMeanF1', ...
        'MeanPairedDifference', 'CI95Lower', 'CI95Upper', 'LLGDWins'});
    outputFile = char(outputFile);
    outputFolder = fileparts(outputFile);
    if ~isempty(outputFolder) && ~isfolder(outputFolder)
        mkdir(outputFolder);
    end
    writetable(results, outputFile);
    fprintf('Saved paired F1 intervals to %s\n', outputFile);
end
