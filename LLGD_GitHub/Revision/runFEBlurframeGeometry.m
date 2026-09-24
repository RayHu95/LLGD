function [metrics, lineDetail, packetDetail, config] = runFEBlurframeGeometry(config)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'LineDetection')));
    addpath(fileparts(mfilename('fullpath')));

    defaults = defaultConfiguration(codeRoot);
    if nargin < 1 || isempty(config)
        config = defaults;
    else
        config = mergeConfiguration(defaults, config);
    end
    annotations = readAnnotations(config.annotationFile);
    annotations = selectAnnotations(annotations, config);
    [rawFolder, createdStaging, createdRoot] = prepareRawData(config);
    stagingCleanup = onCleanup(@() removeStaging(rawFolder, ...
        config.stagingFolder, createdStaging, createdRoot, config.keepStaging));

    predictions = repmat(emptyPrediction(), numel(annotations), 1);
    groundTruth = repmat(emptyGroundTruth(), numel(annotations), 1);
    lineRows = repmat(emptyLineRow(), 0, 1);
    packetRows = repmat(emptyPacketRow(), numel(annotations), 1);
    evalConfig.detectorParameters = config.detectorParameters;
    for i = 1:numel(annotations)
        current = annotations(i);
        eventFile = fullfile(rawFolder, strrep(current.filename, '.png', '.npz'));
        eventArray = readEventPacket(eventFile, config.stagingFolder, ...
            config.eventWidth, config.eventHeight);
        timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
        rng(config.seed + 100000 + current.sourceIndex * 1000 + 1, 'twister');
        [labels, runtime] = evaluateComparisonPacket('LLGD', eventArray, ...
            config.eventWidth, config.eventHeight, timestamp(1), evalConfig);
        [linePred, lineScore, clusterId] = labelsToSegments(eventArray, labels, ...
            config.eventWidth, config.eventHeight, current.width, current.height, ...
            config.exposureTime);

        predictions(i).line_pred = linePred;
        predictions(i).line_score = lineScore;
        predictions(i).filename = current.filename;
        predictions(i).width = current.width;
        predictions(i).height = current.height;
        groundTruth(i).filename = current.filename;
        groundTruth(i).width = current.width;
        groundTruth(i).height = current.height;
        groundTruth(i).lines = current.lines;

        packetRows(i).Filename = string(current.filename);
        packetRows(i).EventCount = size(eventArray, 1);
        packetRows(i).ClusterCount = numel(unique(labels(labels > 0)));
        packetRows(i).SegmentCount = numel(lineScore);
        packetRows(i).RuntimeSeconds = runtime;
        for j = 1:numel(lineScore)
            row = emptyLineRow();
            row.Filename = string(current.filename);
            row.Line = j;
            row.Cluster = clusterId(j);
            row.Score = lineScore(j);
            row.X1 = linePred(j, 1, 1);
            row.Y1 = linePred(j, 1, 2);
            row.X2 = linePred(j, 2, 1);
            row.Y2 = linePred(j, 2, 2);
            lineRows(end + 1, 1) = row;
        end
        fprintf('[%d/%d] %s, %d events, %d segments\n', i, ...
            numel(annotations), current.filename, size(eventArray, 1), numel(lineScore));
    end

    if ~isfolder(config.outputFolder)
        mkdir(config.outputFolder);
    end
    gtFile = fullfile(config.outputFolder, [config.resultPrefix, '_gt.json']);
    resultFile = fullfile(config.outputFolder, [config.resultPrefix, '_result.json']);
    writeJSON(gtFile, groundTruth);
    writeJSON(resultFile, predictions);
    lineDetail = struct2table(lineRows);
    packetDetail = struct2table(packetRows);
    writetable(lineDetail, fullfile(config.outputFolder, ...
        [config.resultPrefix, '_lines.csv']));
    writetable(packetDetail, fullfile(config.outputFolder, ...
        [config.resultPrefix, '_packets.csv']));
    metrics = evaluateStructuralAP(gtFile, resultFile);
    writetable(metrics, fullfile(config.outputFolder, ...
        [config.resultPrefix, '_metrics.csv']));
    clear stagingCleanup;
end

function config = defaultConfiguration(codeRoot)
    materialRoot = fullfile(codeRoot, 'external');
    config.annotationFile = fullfile(materialRoot, 'FE-Blurframe', 'test.jsonl');
    config.rawZip = fullfile(materialRoot, 'RE-LSD', 'events_FE-LSD_600.zip');
    config.stagingFolder = fullfile(codeRoot, 'tmp', 'fe_blurframe');
    config.rawFolder = fullfile(config.stagingFolder, 'events_raw');
    config.outputFolder = fullfile(codeRoot, 'Revision', 'results');
    config.resultPrefix = 'fe_blurframe_llgd';
    config.manifestFile = fullfile(codeRoot, 'Revision', 'third_party', ...
        'FE-LSD', 'dataset', 'FE-Blurframe-154', 'subset_manifest.csv');
    config.packetFiles = {};
    config.maxPackets = inf;
    config.keepStaging = false;
    config.seed = 2025;
    config.eventWidth = 320;
    config.eventHeight = 256;
    config.exposureTime = 0.03;
    config.detectorParameters = struct('MADThreshold', 3.5, ...
        'PinThreshold', 0.8, 'PwThreshold', 0.8, ...
        'OverlapThreshold', 0.8, 'Eps1', 0.02, 'Eps2', 0.02, ...
        'UseWeights', true, 'UseVerification', true, ...
        'UseGlobalExpansion', true);
end

function annotations = readAnnotations(filename)
    fid = fopen(filename, 'r');
    fileCleanup = onCleanup(@() fclose(fid));
    annotations = repmat(struct('filename', '', 'width', 0, 'height', 0, ...
        'lines', [], 'sourceIndex', 0), 0, 1);
    sourceIndex = 0;
    line = fgetl(fid);
    while ischar(line)
        sourceIndex = sourceIndex + 1;
        value = jsondecode(line);
        fileId = str2double(strrep(value.filename, '.png', ''));
        if fileId <= 600
            current.filename = value.filename;
            current.width = double(value.image_size(1));
            current.height = double(value.image_size(2));
            current.lines = double(value.lines);
            current.sourceIndex = sourceIndex;
            annotations(end + 1, 1) = current;
        end
        line = fgetl(fid);
    end
    clear fileCleanup;
end

function annotations = selectAnnotations(annotations, config)
    if ~isempty(config.manifestFile)
        manifest = readtable(config.manifestFile);
        filenames = cellstr(string(manifest{:, 1}));
        [found, order] = ismember(filenames, {annotations.filename});
        if ~all(found)
            error('The subset manifest does not match the annotations.');
        end
        annotations = annotations(order);
    end
    if ~isempty(config.packetFiles)
        annotations = annotations(ismember({annotations.filename}, config.packetFiles));
    end
    annotations = annotations(1:min(numel(annotations), config.maxPackets));
end

function [rawFolder, createdStaging, createdRoot] = prepareRawData(config)
    rawFolder = config.rawFolder;
    createdStaging = false;
    createdRoot = false;
    if isfolder(rawFolder)
        return;
    end
    if ~isfolder(config.stagingFolder)
        mkdir(config.stagingFolder);
        createdRoot = true;
    end
    unzip(config.rawZip, config.stagingFolder);
    createdStaging = true;
end

function eventArray = readEventPacket(filename, stagingFolder, eventWidth, eventHeight)
    [~, name] = fileparts(filename);
    sampleFolder = fullfile(stagingFolder, 'npy', name);
    if isfolder(sampleFolder)
        rmdir(sampleFolder, 's');
    end
    mkdir(sampleFolder);
    sampleCleanup = onCleanup(@() removeFolder(sampleFolder));
    unzip(filename, sampleFolder);
    x = double(readNPYVector(fullfile(sampleFolder, 'x.npy')));
    y = double(readNPYVector(fullfile(sampleFolder, 'y.npy')));
    t = double(readNPYVector(fullfile(sampleFolder, 't.npy')));
    p = double(readNPYVector(fullfile(sampleFolder, 'p.npy')));
    keep = x >= 0 & x < eventWidth & y >= 0 & y < eventHeight;
    x = x(keep);
    y = y(keep);
    t = t(keep);
    p = p(keep);
    eventArray = [x, y, p, zeros(size(t)), t];
    clear sampleCleanup;
end

function data = readNPYVector(filename)
    fid = fopen(filename, 'r', 'ieee-le');
    fileCleanup = onCleanup(@() fclose(fid));
    magic = fread(fid, 6, '*uint8')';
    if ~isequal(magic, uint8([147, double('NUMPY')]))
        error('Invalid NPY file: %s', filename);
    end
    version = fread(fid, 2, '*uint8');
    if version(1) == 1
        headerLength = fread(fid, 1, 'uint16');
    else
        headerLength = fread(fid, 1, 'uint32');
    end
    header = char(fread(fid, headerLength, '*char')');
    token = regexp(header, '''descr'':\s*''([^'']+)''', 'tokens', 'once');
    switch token{1}
        case {'<i2', '|i2'}
            precision = 'int16';
        case {'<i4', '|i4'}
            precision = 'int32';
        case {'<i8', '|i8'}
            precision = 'int64';
        case {'|b1', '|u1'}
            precision = 'uint8';
        case '<f4'
            precision = 'single';
        otherwise
            error('Unsupported NPY type: %s', token{1});
    end
    data = fread(fid, inf, ['*', precision]);
    clear fileCleanup;
end

function [linePred, lineScore, clusterId] = labelsToSegments(eventArray, ...
        labels, eventWidth, eventHeight, imageWidth, imageHeight, exposureTime)
    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    pointData = [eventArray(:, 1) / eventWidth, ...
        eventArray(:, 2) / eventHeight, timestamp];
    ids = unique(labels(labels > 0));
    segments = zeros(numel(ids), 4);
    lineScore = zeros(numel(ids), 1);
    clusterId = zeros(numel(ids), 1);
    lineNum = 0;
    for i = 1:numel(ids)
        idx = labels == ids(i);
        points = pointData(idx, :);
        center = mean(points, 1);
        [~, ~, V] = svd(points - center, 0);
        normal = V(:, end);
        d = -normal' * center';
        A = normal(1) / eventWidth;
        B = normal(2) / eventHeight;
        C = normal(3) * exposureTime + d;
        normalSquared = A^2 + B^2;
        if normalSquared <= eps
            continue;
        end
        xy = eventArray(idx, 1:2);
        offset = (xy * [A; B] + C) / normalSquared;
        projected = xy - offset .* [A, B];
        direction = [-B, A] / sqrt(normalSquared);
        position = projected * direction';
        [~, first] = min(position);
        [~, last] = max(position);
        [point1, point2, valid] = clipSegment(projected(first, :), ...
            projected(last, :), eventWidth, eventHeight);
        if ~valid
            continue;
        end
        lineNum = lineNum + 1;
        scale = [imageWidth / eventWidth, imageHeight / eventHeight];
        point1 = point1 .* scale;
        point2 = point2 .* scale;
        segments(lineNum, :) = [point1, point2];
        lineScore(lineNum) = sum(idx) / size(eventArray, 1);
        clusterId(lineNum) = ids(i);
    end
    segments = segments(1:lineNum, :);
    lineScore = lineScore(1:lineNum);
    clusterId = clusterId(1:lineNum);
    linePred = zeros(lineNum, 2, 2);
    linePred(:, 1, 1) = segments(:, 1);
    linePred(:, 1, 2) = segments(:, 2);
    linePred(:, 2, 1) = segments(:, 3);
    linePred(:, 2, 2) = segments(:, 4);
end

function [point1, point2, valid] = clipSegment(point1, point2, width, height)
    delta = point2 - point1;
    p = [-delta(1), delta(1), -delta(2), delta(2)];
    q = [point1(1), width - point1(1), point1(2), height - point1(2)];
    lower = 0;
    upper = 1;
    valid = true;
    for i = 1:4
        if abs(p(i)) <= eps
            if q(i) < 0
                valid = false;
                return;
            end
        else
            ratio = q(i) / p(i);
            if p(i) < 0
                lower = max(lower, ratio);
            else
                upper = min(upper, ratio);
            end
        end
    end
    if lower > upper
        valid = false;
        return;
    end
    original = point1;
    point1 = original + lower * delta;
    point2 = original + upper * delta;
    point1 = min(max(point1, [0, 0]), [width, height]);
    point2 = min(max(point2, [0, 0]), [width, height]);
    valid = norm(point2 - point1) > eps;
end

function writeJSON(filename, value)
    fid = fopen(filename, 'w');
    fileCleanup = onCleanup(@() fclose(fid));
    if isstruct(value) && isfield(value, 'line_score')
        for i = 1:numel(value)
            value(i).line_score = num2cell(value(i).line_score(:));
        end
    end
    text = jsonencode(value);
    if isstruct(value) && isscalar(value)
        text = ['[', text, ']'];
    end
    fwrite(fid, text, 'char');
    clear fileCleanup;
end

function removeStaging(rawFolder, stagingFolder, createdStaging, createdRoot, keepStaging)
    if keepStaging || ~createdStaging
        return;
    end
    removeFolder(rawFolder);
    npyFolder = fullfile(stagingFolder, 'npy');
    removeFolder(npyFolder);
    if createdRoot && isfolder(stagingFolder)
        rmdir(stagingFolder);
    end
end

function removeFolder(folder)
    if isfolder(folder)
        rmdir(folder, 's');
    end
end

function config = mergeConfiguration(defaults, supplied)
    config = defaults;
    names = fieldnames(supplied);
    for i = 1:numel(names)
        name = names{i};
        if isfield(config, name) && isstruct(config.(name)) && isstruct(supplied.(name))
            config.(name) = mergeConfiguration(config.(name), supplied.(name));
        else
            config.(name) = supplied.(name);
        end
    end
end

function value = emptyPrediction()
    value = struct('line_pred', zeros(0, 2, 2), 'line_score', zeros(0, 1), ...
        'filename', '', 'width', 0, 'height', 0);
end

function value = emptyGroundTruth()
    value = struct('filename', '', 'width', 0, 'height', 0, 'lines', zeros(0, 4));
end

function row = emptyLineRow()
    row = struct('Filename', "", 'Line', 0, 'Cluster', 0, 'Score', 0, ...
        'X1', NaN, 'Y1', NaN, 'X2', NaN, 'Y2', NaN);
end

function row = emptyPacketRow()
    row = struct('Filename', "", 'EventCount', 0, 'ClusterCount', 0, ...
        'SegmentCount', 0, 'RuntimeSeconds', NaN);
end
