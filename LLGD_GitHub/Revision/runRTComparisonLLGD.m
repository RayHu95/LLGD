function runRTComparisonLLGD(sequenceIndices, useVerification, outputRoot)
    if nargin < 1
        sequenceIndices = 1:3;
    end
    if nargin < 2
        useVerification = true;
    end
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'LineDetection')));
    addpath(fileparts(mfilename('fullpath')));
    inputRoot = fullfile(codeRoot, 'Revision', 'results', 'rt_evldt');
    if nargin < 3
        outputRoot = inputRoot;
    end
    names = {'urban', 'office_spiral', 'hqf_boxes'};
    config.detectorParameters = struct('MADThreshold', 3.5, ...
        'PinThreshold', 0.8, 'PwThreshold', 0.8, ...
        'OverlapThreshold', 0.8, 'Eps1', 0.02, 'Eps2', 0.02, ...
        'UseWeights', true, 'UseVerification', useVerification, ...
        'UseGlobalExpansion', true);
    for s = sequenceIndices
        inputFolder = fullfile(inputRoot, names{s});
        folder = fullfile(outputRoot, names{s});
        if ~isfolder(folder), mkdir(folder); end
        frames = jsondecode(fileread(fullfile(inputFolder, 'frames.json')));
        lineRows = zeros(0, 7);
        packetRows = zeros(numel(frames), 4);
        for i = 1:numel(frames)
            index = frames(i).index;
            data = load(fullfile(inputFolder, sprintf('%06d.mat', index)));
            rng(2025 + s * 100000 + index * 1000 + 1, 'twister');
            [labels, runtime] = evaluateComparisonPacket('LLGD', ...
                data.eventArray, 240, 180, 0, config);
            tic;
            [segments, scores] = labelsToSegments(data.eventArray, labels, 240, 180, .020);
            runtime = runtime + toc;
            lineRows = [lineRows; repmat([index, frames(i).tick], ...
                size(segments, 1), 1), segments, scores];
            packetRows(i, :) = [index, size(data.eventArray, 1), size(segments, 1), runtime];
            save(fullfile(folder, sprintf('%06d_labels.mat', index)), 'labels');
            fprintf('%s [%d/%d], %d events, %d segments, %.3f s\n', ...
                names{s}, i, numel(frames), packetRows(i, 2:4));
        end
        writetable(array2table(lineRows, 'VariableNames', ...
            {'Index','Tick','X1','Y1','X2','Y2','Score'}), fullfile(folder, 'llgd_lines.csv'));
        writetable(array2table(packetRows, 'VariableNames', ...
            {'Index','Events','Segments','Seconds'}), fullfile(folder, 'llgd_timing.csv'));
    end
end

function [segments, scores] = labelsToSegments(eventArray, labels, width, height, endTime)
    t = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    pointData = [eventArray(:, 1) / width, eventArray(:, 2) / height, t];
    ids = unique(labels(labels > 0));
    segments = zeros(0, 4);
    scores = zeros(0, 1);
    for i = 1:numel(ids)
        idx = labels == ids(i);
        points = pointData(idx, :);
        center = mean(points, 1);
        [~, ~, V] = svd(points - center, 0);
        normal = V(:, end);
        d = -normal' * center';
        A = normal(1) / width;
        B = normal(2) / height;
        C = normal(3) * endTime + d;
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
        [p1, p2, valid] = clipSegment(projected(first, :), projected(last, :), width, height);
        if valid
            segments(end + 1, :) = [p1, p2];
            scores(end + 1, 1) = sum(idx) / numel(labels);
        end
    end
end

function [p1, p2, valid] = clipSegment(p1, p2, width, height)
    delta = p2 - p1;
    p = [-delta(1), delta(1), -delta(2), delta(2)];
    q = [p1(1), width - p1(1), p1(2), height - p1(2)];
    lower = 0;
    upper = 1;
    valid = true;
    for i = 1:4
        if abs(p(i)) <= eps
            if q(i) < 0
                valid = false;
                return;
            end
        elseif p(i) < 0
            lower = max(lower, q(i) / p(i));
        else
            upper = min(upper, q(i) / p(i));
        end
    end
    if lower > upper
        valid = false;
        return;
    end
    original = p1;
    p1 = min(max(original + lower * delta, [0, 0]), [width, height]);
    p2 = min(max(original + upper * delta, [0, 0]), [width, height]);
    valid = norm(p2 - p1) > eps;
end
