public class CallQaService {

    @InvocableMethod
    public static List<Integer> scoreCalls(List<String> transcripts) {

        List<Integer> scores = new List<Integer>();

        for(String transcript : transcripts){

            Integer score = 0;

            if(transcript.containsIgnoreCase('injury'))
                score += 20;

            if(transcript.containsIgnoreCase('accident'))
                score += 20;

            if(transcript.containsIgnoreCase('insurance'))
                score += 20;

            if(transcript.containsIgnoreCase('attorney'))
                score += 20;

            if(transcript.length() > 500)
                score += 20;

            scores.add(score);
        }

        return scores;
    }
}