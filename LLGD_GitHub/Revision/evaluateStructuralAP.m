function [summary, curves] = evaluateStructuralAP(gtFile, predictionFile)
    groundTruth = jsondecode(fileread(gtFile));
    predictions = jsondecode(fileread(predictionFile));
    if numel(groundTruth) ~= numel(predictions)
        error('Ground truth and prediction counts do not match.');
    end

    lineGroundTruth = cell(numel(groundTruth), 1);
    linePrediction = zeros(0, 2, 2);
    lineScore = zeros(0, 1);
    imageId = zeros(0, 1);
    for i = 1:numel(groundTruth)
        sx = 128 / double(groundTruth(i).width);
        sy = 128 / double(groundTruth(i).height);
        currentGroundTruth = double(groundTruth(i).lines);
        currentGroundTruth = reshape(currentGroundTruth, [], 4);
        lines = zeros(size(currentGroundTruth, 1), 2, 2);
        lines(:, 1, 1) = currentGroundTruth(:, 1) * sx;
        lines(:, 1, 2) = currentGroundTruth(:, 2) * sy;
        lines(:, 2, 1) = currentGroundTruth(:, 3) * sx;
        lines(:, 2, 2) = currentGroundTruth(:, 4) * sy;
        lineGroundTruth{i} = lines;

        currentPrediction = double(predictions(i).line_pred);
        currentScore = double(predictions(i).line_score(:));
        if isempty(currentScore)
            continue;
        end
        currentPrediction = reshape(currentPrediction, [], 2, 2);
        currentPrediction(:, :, 1) = currentPrediction(:, :, 1) * sx;
        currentPrediction(:, :, 2) = currentPrediction(:, :, 2) * sy;
        linePrediction = cat(1, linePrediction, currentPrediction);
        lineScore = [lineScore; currentScore];
        imageId = [imageId; repmat(i, numel(currentScore), 1)];
    end

    [~, order] = sort(lineScore, 'descend');
    linePrediction = linePrediction(order, :, :);
    imageId = imageId(order);
    thresholds = [5, 10, 15];
    sAP = zeros(size(thresholds));
    precision = zeros(size(thresholds));
    recall = zeros(size(thresholds));
    curves = repmat(struct('Threshold', 0, 'Recall', [], 'Precision', []), ...
        numel(thresholds), 1);
    for i = 1:numel(thresholds)
        [sAP(i), precision(i), recall(i), rcs, prs] = calculateAP( ...
            lineGroundTruth, linePrediction, imageId, thresholds(i));
        curves(i).Threshold = thresholds(i);
        curves(i).Recall = rcs;
        curves(i).Precision = prs;
    end

    summary = table(sAP(1), sAP(2), sAP(3), mean(sAP), ...
        mean(precision), mean(recall), ...
        sum(cellfun(@(x) size(x, 1), lineGroundTruth)), size(linePrediction, 1), ...
        'VariableNames', {'sAP5', 'sAP10', 'sAP15', 'msAP', ...
        'Precision', 'Recall', 'GroundTruthLines', 'PredictedLines'});
end

function [AP, P, R, rcs, prs] = calculateAP(lineGroundTruth, ...
        linePrediction, imageId, threshold)
    groundTruthNum = sum(cellfun(@(x) size(x, 1), lineGroundTruth));
    predictionNum = size(linePrediction, 1);
    truePositive = zeros(predictionNum, 1);
    falsePositive = zeros(predictionNum, 1);
    hits = cellfun(@(x) false(size(x, 1), 1), lineGroundTruth, ...
        'UniformOutput', false);

    for i = 1:predictionNum
        currentGroundTruth = lineGroundTruth{imageId(i)};
        if isempty(currentGroundTruth)
            falsePositive(i) = 1;
            continue;
        end
        currentPrediction = linePrediction(i, :, :);
        distance1 = sum(sum((currentGroundTruth - currentPrediction).^2, 3), 2);
        distance2 = sum(sum((currentGroundTruth - currentPrediction(:, [2, 1], :)).^2, 3), 2);
        [distance, choice] = min(min(distance1, distance2));
        if distance < threshold && ~hits{imageId(i)}(choice)
            truePositive(i) = 1;
            hits{imageId(i)}(choice) = true;
        else
            falsePositive(i) = 1;
        end
    end

    if groundTruthNum == 0
        rcs = zeros(predictionNum, 1);
        prs = zeros(predictionNum, 1);
        AP = 0;
        P = 0;
        R = 0;
        return;
    end
    truePositive = cumsum(truePositive) / groundTruthNum;
    falsePositive = cumsum(falsePositive) / groundTruthNum;
    rcs = truePositive;
    prs = truePositive ./ max(truePositive + falsePositive, 1e-9);
    AP = integrateAP(rcs, prs) * 100;
    if predictionNum == 0
        P = 0;
        R = 0;
    else
        P = prs(end) * 100;
        R = rcs(end) * 100;
    end
end

function AP = integrateAP(recall, precision)
    recall = [0; recall; 1];
    precision = [0; precision; 0];
    for i = numel(precision):-1:2
        precision(i - 1) = max(precision(i - 1), precision(i));
    end
    idx = find(recall(2:end) ~= recall(1:end - 1));
    AP = sum((recall(idx + 1) - recall(idx)) .* precision(idx + 1));
end
