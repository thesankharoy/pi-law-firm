public with sharing class ActivityTimelinePdfController {

    public List<PdfActivity> pdfActivities { get; set; }

    public ActivityTimelinePdfController() {

        pdfActivities = new List<PdfActivity>();

        Id recordId =
            (Id)ApexPages.currentPage().getParameters().get('id');

        if(recordId != null) {

            List<ActivityTimelineController.MonthGroup> data =
                ActivityTimelineController.getTimeline(recordId);

            for(ActivityTimelineController.MonthGroup g : data) {

                for(ActivityTimelineController.ActivityItem a : g.activities) {

                    PdfActivity p = new PdfActivity();

                    p.subject = a.subject;
                    p.status = a.status;
                    p.type = a.type;
                    p.displayDate = a.displayDate;

                    pdfActivities.add(p);
                }
            }
        }
    }

 public class PdfActivity {
    public String subject { get; set; }
    public String status { get; set; }
    public String type { get; set; }
    public String displayDate { get; set; }
}
    @AuraEnabled
public static String generatePdf(Id recordId) {

    PageReference pdfPage = Page.ActivityTimelinePdf;

    pdfPage.getParameters().put('id', String.valueOf(recordId));

    return pdfPage.getUrl() + '&isdtp=1';
}
}