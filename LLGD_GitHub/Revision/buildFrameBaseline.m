function [baseline, lines] = buildFrameBaseline(data)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'frameGT')));

    lines = frameLSD(data);
    baseline = repmat(struct('labels', [], 'label_num', 0, ...
        'line_num', 0, 'event_num', 0), numel(data), 1);
    for i = 1:numel(data)
        eventArray = data(i).events;
        lines{i} = sortFrameLines(lines{i});
        labels = assignFrameLabels(eventArray(:, 1:3), lines{i});
        baseline(i).labels = labels;
        baseline(i).label_num = numel(unique(labels(labels > 0)));
        baseline(i).line_num = numel(lines{i});
        baseline(i).event_num = size(eventArray, 1);
    end
end

function labels = assignFrameLabels(events, frameLines)
    eventNum = size(events, 1);
    lineNum = numel(frameLines);
    labels = zeros(eventNum, 1);
    if eventNum == 0 || lineNum == 0
        return;
    end

    x = double(events(:, 1)) + 1;
    y = double(events(:, 2)) + 1;
    candidateDistances = inf(eventNum, lineNum);
    threshold = 2;
    for j = 1:lineNum
        slope = frameLines(j).slope;
        intercept = frameLines(j).intercept;
        if isinf(slope)
            distance = abs(x - intercept);
        else
            distance = abs(slope * x + intercept - y) / sqrt(slope^2 + 1);
        end

        center = frameLines(j).center;
        halfLength = frameLines(j).length / 2;
        centerDistance = hypot(x - center(1), y - center(2));
        candidate = distance < threshold & centerDistance < halfLength + threshold;
        inside = centerDistance < halfLength - 1;
        candidateNum = sum(candidate);
        if candidateNum > 0 && sum(candidate & inside) / candidateNum < 0.35
            candidate = candidate & inside;
        end
        candidateDistances(candidate, j) = distance(candidate);
    end

    [bestDistance, bestLine] = min(candidateDistances, [], 2);
    labels(isfinite(bestDistance)) = bestLine(isfinite(bestDistance));
end

function frameLines = sortFrameLines(frameLines)
    if numel(frameLines) < 2
        return;
    end

    keys = zeros(numel(frameLines), 6);
    for i = 1:numel(frameLines)
        keys(i, :) = [double(frameLines(i).center(:))', ...
            mod(double(frameLines(i).angle), 180), double(frameLines(i).length), ...
            double(frameLines(i).slope), double(frameLines(i).intercept)];
    end
    [~, order] = sortrows(keys, 1:size(keys, 2));
    frameLines = frameLines(order);
end
