function plotLocalVerification()
    outputFolder = fullfile(fileparts(mfilename('fullpath')), 'results', 'component_split');
    S = load(fullfile(outputFolder, 'local_samples.mat'));
    R = load(fullfile(outputFolder, 'local_verification_results.mat'), 'predictions');
    names = {'corner','cross','noise'};
    figure('Visible','off','Color','w','Units','centimeters','Position',[2,2,18,10]);
    for c = 1:3
        candidates = strcmp({S.samples.Case}, names{c}) & ...
            [S.samples.Multiplicity]==3 & [S.samples.Rotation]==0 & ...
            [S.samples.Opening]==90 & [S.samples.Repeat]==1;
        if c < 3, candidates = candidates & [S.samples.NoiseRatio]==0.25; end
        i = find(candidates,1);
        s = S.samples(i);
        for row = 1:2
            subplot(2,3,(row-1)*3+c); hold on;
            [p,~,idx] = unique(s.Points,'rows');
            counts = accumarray(idx,1);
            scatter(p(:,1)-120,p(:,2)-90,8+8*counts,[0.35,0.35,0.35],'filled');
            if row == 1
                models = s.Models;
            else
                models = R.predictions{i,1};
            end
            colors = [0.78,0.12,0.12; 0.0,0.32,0.7];
            for j = 1:size(models,1)
                a = models(j,1); b = models(j,2);
                d = models(j,3)+120*a+90*b;
                if row==1
                    direction = [-b,a];
                    localSupport = s.Support{j}-[120,90];
                    span = localSupport*direction';
                    endpoints = [min(span);max(span)]*direction-d*[a,b];
                    x = endpoints(:,1); y = endpoints(:,2);
                elseif abs(b)>=abs(a)
                    x = [-5,5]; y = -(a*x+d)/b;
                else
                    y = [-4,4]; x = -(b*y+d)/a;
                end
                plot(x,y,'Color',colors(j,:),'LineWidth',1.2);
            end
            axis equal; xlim([-5,5]); ylim([-4,4]);
            set(gca,'FontName','Times New Roman','FontSize',9,'Box','on','XTick',[-4,0,4],'YTick',[-3,0,3]);
            xlabel('u (pixel)'); ylabel('v (pixel)');
            if row==1
                if c==3, title('Noise-only input');
                else, title([upper(names{c}(1)),names{c}(2:end),': imposed lines']); end
            elseif size(models,1)==1
                title('Full module: 1 line');
            else
                title(sprintf('Full module: %d lines',size(models,1)));
            end
        end
    end
    set(gcf,'PaperUnits','centimeters','PaperSize',[18,10], ...
        'PaperPosition',[0,0,18,10]);
    print(gcf,fullfile(outputFolder,'LocalVerificationExamples.pdf'),'-dpdf','-painters');
    close(gcf);
end
