use serde::{Deserialize, Serialize, Deserializer};
use reqwest::blocking::Client;
use reqwest::header::USER_AGENT;
use anyhow::{Result, anyhow};


fn deserialize_u32_or_str_option<'de, D>(deserializer: D) -> std::result::Result<Option<u32>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde_json::Value;
    let v: Value = Deserialize::deserialize(deserializer)?;
    match v {
        Value::Number(n) => Ok(n.as_u64().map(|x| x as u32)),
        Value::String(s) => {
            if s.is_empty() {
                Ok(None)
            } else {
                Ok(s.parse::<u32>().ok())
            }
        },
        _ => Ok(None),
    }
}

fn deserialize_u64_or_str_option<'de, D>(deserializer: D) -> std::result::Result<Option<u64>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde_json::Value;
    let v: Value = Deserialize::deserialize(deserializer)?;
    match v {
        Value::Number(n) => Ok(n.as_u64()),
        Value::String(s) => {
            if s.is_empty() {
                Ok(None)
            } else {
                Ok(s.parse::<u64>().ok())
            }
        },
        _ => Ok(None),
    }
}

// Helper to deserialize RecentAchievements which can be [] (empty array) or {} (empty/populated object)
fn deserialize_recent_achievements<'de, D>(deserializer: D) -> std::result::Result<std::collections::HashMap<String, std::collections::HashMap<String, RecentAchievement>>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde_json::Value;
    let v: Value = Deserialize::deserialize(deserializer)?;
    match v {
        Value::Array(_) => Ok(std::collections::HashMap::new()), // Empty array means no achievements
        Value::Object(map) => {
            // Try to deserialize the object as the expected HashMap
            serde_json::from_value(Value::Object(map)).map_err(serde::de::Error::custom)
        },
        _ => Ok(std::collections::HashMap::new()),
    }
}


const BASE_URL: &str = "https://retroachievements.org/API";

#[derive(Clone)]
pub struct RetroAchievementsClient {
    username: String,
    api_key: String,
    client: Client,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserProfile {
    #[serde(rename = "User")]
    pub user: String,
    #[serde(rename = "RichPresenceMsg")]
    pub rich_presence_msg: Option<String>,
    #[serde(rename = "LastGameID")]
    pub last_game_id: Option<u64>,
    #[serde(rename = "ContribCount")]
    pub contrib_count: Option<u64>,
    #[serde(rename = "Motto")]
    pub motto: Option<String>,
}

#[derive(Debug, Default, Deserialize, Serialize)]
pub struct GameInfo {
    #[serde(rename = "ID")]
    pub id: Option<u64>,     // Was u64
    #[serde(rename = "Title")]
    pub title: Option<String>, // Was String
    #[serde(rename = "ConsoleID")]
    pub console_id: Option<u64>, // Was u64
    #[serde(rename = "ForumTopicID")]
    pub forum_topic_id: Option<u64>,
    #[serde(rename = "Flags")]
    pub flags: Option<u64>,
    #[serde(rename = "ImageIcon")]
    pub image_icon: Option<String>,
    #[serde(rename = "ImageTitle")]
    pub image_title: Option<String>,
    #[serde(rename = "ImageIngame")]
    pub image_ingame: Option<String>,
    #[serde(rename = "ImageBoxArt")]
    pub image_box_art: Option<String>,
    #[serde(rename = "Publisher")]
    pub publisher: Option<String>,
    #[serde(rename = "Developer")]
    pub developer: Option<String>,
    #[serde(rename = "Genre")]
    pub genre: Option<String>,
    #[serde(rename = "Released")]
    pub released: Option<String>,
    #[serde(rename = "IsFinal")]
    #[serde(default)] 
    pub is_final: bool,
    #[serde(rename = "ConsoleName")]
    pub console_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GameListEntry {
    #[serde(rename = "ID")]
    pub id: u64,
    #[serde(rename = "Title")]
    pub title: String,
    #[serde(rename = "ConsoleID")]
    pub console_id: u64,
    #[serde(rename = "ImageIcon")]
    pub image_icon: Option<String>,
    #[serde(rename = "Hashes")]
    pub hashes: Option<Vec<String>>, // Hypothetical, but we'll focus on Title/ID
}

#[derive(Debug, Deserialize)]
struct HashResponse {
    #[serde(rename = "GameID")]
    game_id: u64,
    #[serde(rename = "ConsoleID")]
    console_id: u64,
    #[serde(rename = "ConsoleName")]
    console_name: String,
    #[serde(rename = "ForumTopicID")]
    forum_topic_id: Option<u64>,
    #[serde(rename = "Flags")]
    flags: Option<u64>,
    #[serde(rename = "ImageIcon")]
    image_icon: String,
    #[serde(rename = "ImageTitle")]
    image_title: String,
    #[serde(rename = "ImageIngame")]
    image_ingame: String,
    #[serde(rename = "ImageBoxArt")]
    image_box_art: String,
    #[serde(rename = "Publisher")]
    publisher: String,
    #[serde(rename = "Developer")]
    developer: String,
    #[serde(rename = "Genre")]
    genre: String,
    #[serde(rename = "Released")]
    released: Option<String>,
    #[serde(rename = "IsFinal")]
    is_final: Option<bool>, // API might return this differently than GameInfo
    #[serde(rename = "Title")]
    title: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ConsoleIdEntry {
    #[serde(rename = "ID")]
    pub id: u64,
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Active")]
    pub active: Option<bool>,
}


#[derive(Debug, Default, Deserialize, Serialize, Clone)]
pub struct Achievement {
    #[serde(rename = "ID", deserialize_with = "deserialize_u64_or_str_option")]
    pub id: Option<u64>,
    #[serde(rename = "Title")]
    pub title: String,
    #[serde(rename = "Description")]
    pub description: String,
    #[serde(rename = "Points", deserialize_with = "deserialize_u32_or_str_option")]
    pub points: Option<u32>,
    #[serde(rename = "BadgeName")]
    pub badge_name: String,
    #[serde(rename = "DateEarned")]
    pub date_earned: Option<String>,
    #[serde(rename = "DateEarnedHardcore")]
    pub date_earned_hardcore: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct RecentAchievement {
    #[serde(rename = "ID", deserialize_with = "deserialize_u64_or_str_option")]
    pub id: Option<u64>,
    #[serde(rename = "GameID", deserialize_with = "deserialize_u64_or_str_option")]
    pub game_id: Option<u64>,
    #[serde(rename = "GameTitle")]
    pub game_title: Option<String>,
    #[serde(rename = "Title")]
    pub title: String,
    #[serde(rename = "Description")]
    pub description: Option<String>,
    #[serde(rename = "Points", deserialize_with = "deserialize_u32_or_str_option")]
    pub points: Option<u32>,
    #[serde(rename = "BadgeName")]
    pub badge_name: String,
    #[serde(rename = "IsAwarded", deserialize_with = "deserialize_u32_or_str_option")]
    pub is_awarded: Option<u32>,
    #[serde(rename = "DateAwarded")]
    pub date_awarded: Option<String>,
    #[serde(rename = "HardcoreAchieved", deserialize_with = "deserialize_u32_or_str_option")]
    pub hardcore_achieved: Option<u32>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct RecentlyPlayedGame {
    #[serde(rename = "GameID", deserialize_with = "deserialize_u64_or_str_option")]
    pub game_id: Option<u64>,
    #[serde(rename = "ConsoleID", deserialize_with = "deserialize_u32_or_str_option")]
    pub console_id: Option<u32>,
    #[serde(rename = "ConsoleName")]
    pub console_name: String,
    #[serde(rename = "Title")]
    pub title: String,
    #[serde(rename = "ImageIcon")]
    pub image_icon: String,
    #[serde(rename = "LastPlayed")]
    pub last_played: String,
    #[serde(rename = "AchievementsTotal", deserialize_with = "deserialize_u32_or_str_option")]
    pub achievements_total: Option<u32>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UserSummary {
    #[serde(rename = "User")]
    pub user: String,
    #[serde(rename = "UserPic")]
    pub user_pic: String,
    #[serde(rename = "MemberSince")]
    pub member_since: Option<String>,
    #[serde(rename = "Motto")]
    pub motto: Option<String>,
    #[serde(rename = "Rank", deserialize_with = "deserialize_u32_or_str_option")]
    pub rank: Option<u32>,
    #[serde(rename = "TotalPoints", deserialize_with = "deserialize_u32_or_str_option")]
    pub total_points: Option<u32>,
    #[serde(rename = "TotalTruePoints", deserialize_with = "deserialize_u32_or_str_option")]
    pub total_true_points: Option<u32>,
    #[serde(rename = "TotalSoftcorePoints", deserialize_with = "deserialize_u32_or_str_option")]
    pub total_softcore_points: Option<u32>,
    #[serde(rename = "TotalRanked", deserialize_with = "deserialize_u32_or_str_option")]
    pub total_ranked: Option<u32>,
    #[serde(rename = "RecentlyPlayed")]
    pub recently_played: Vec<RecentlyPlayedGame>,
    #[serde(rename = "Status")]
    pub status: Option<String>,
    #[serde(rename = "RichPresenceMsg")]
    pub rich_presence_msg: Option<String>,
    #[serde(rename = "Awarded")]
    pub awarded: std::collections::HashMap<String, AwardedGame>,
    #[serde(rename = "RecentAchievements", deserialize_with = "deserialize_recent_achievements")]
    pub recent_achievements: std::collections::HashMap<String, std::collections::HashMap<String, RecentAchievement>>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct AwardedGame {
    #[serde(rename = "NumPossibleAchievements", deserialize_with = "deserialize_u32_or_str_option")]
    pub num_possible_achievements: Option<u32>,
    #[serde(rename = "PossibleScore", deserialize_with = "deserialize_u32_or_str_option")]
    pub possible_score: Option<u32>,
    #[serde(rename = "NumAchieved", deserialize_with = "deserialize_u32_or_str_option")]
    pub num_achieved: Option<u32>,
    #[serde(rename = "ScoreAchieved", deserialize_with = "deserialize_u32_or_str_option")]
    pub score_achieved: Option<u32>,
    #[serde(rename = "NumAchievedHardcore", deserialize_with = "deserialize_u32_or_str_option")]
    pub num_achieved_hardcore: Option<u32>,
    #[serde(rename = "ScoreAchievedHardcore", deserialize_with = "deserialize_u32_or_str_option")]
    pub score_achieved_hardcore: Option<u32>,
}


#[derive(Debug, Default, Deserialize, Serialize)]
pub struct GameInfoAndUserProgress {
    #[serde(rename = "ID")]
    pub id: Option<u64>,
    #[serde(rename = "Title")]
    pub title: Option<String>,
    #[serde(rename = "ConsoleID")]
    pub console_id: Option<u64>,
    #[serde(rename = "ConsoleName")]
    pub console_name: Option<String>,
    #[serde(rename = "ImageIcon")]
    pub image_icon: Option<String>,
    #[serde(rename = "ImageIngame")]
    pub image_ingame: Option<String>,
    #[serde(rename = "ImageBoxArt")]
    pub image_box_art: Option<String>,
    #[serde(rename = "Publisher")]
    pub publisher: Option<String>,
    #[serde(rename = "Developer")]
    pub developer: Option<String>,
    #[serde(rename = "Genre")]
    pub genre: Option<String>,
    #[serde(rename = "Released")]
    pub released: Option<String>,
    
    // Achievement Dict from RA is usually "Achievements": { "123": {...}, "124": {...} }
    // We need to handle this map carefully.
    #[serde(rename = "Achievements")]
    pub achievements: Option<std::collections::HashMap<String, Achievement>>,
    
    // Stats
    #[serde(rename = "NumAwardedToUser")]
    pub num_awarded: Option<u32>,
    #[serde(rename = "NumAwardedToUserHardcore")]
    pub num_awarded_hardcore: Option<u32>,
    #[serde(rename = "NumAchievements")]
    pub total_achievements: Option<u32>, // Sometimes calculated from len logic
}

impl RetroAchievementsClient {
    pub fn new(username: String, api_key: String) -> Self {
        Self {
            username,
            api_key,
            client: Client::new(),
        }
    }

    fn build_url(&self, endpoint: &str) -> String {
        format!(
            "{}/{}?z={}&y={}",
            BASE_URL, endpoint, self.username, self.api_key
        )
    }

    pub fn verify_credentials(&self) -> Result<UserProfile> {
        let url = format!(
            "{}/API_GetUserProfile.php?u={}&y={}&u={}",
            BASE_URL, self.username, self.api_key, self.username
        );

        let response = self.client.get(&url)
            .header(USER_AGENT, "Theophany")
            .send()?;

        if !response.status().is_success() {
             return Err(anyhow!("Failed to verify credentials: {}", response.status()));
        }

        let profile: UserProfile = response.json()?;
        Ok(profile)
    }
    
    pub fn resolve_hash(&self, md5: &str) -> Result<u64> {
         let url = format!("https://retroachievements.org/dorequest.php?r=gameid&m={}", md5);
         let response = self.client.get(&url)
            .header(USER_AGENT, "Theophany")
            .send()?;
            
        if !response.status().is_success() {
             return Err(anyhow!("Failed to resolve hash: {}", response.status()));
        }
        
        let text = response.text()?;
        #[derive(Deserialize)]
        struct GameIDResponse {
            #[serde(rename = "GameID")]
            game_id: u64,
        }
        
        let json: GameIDResponse = serde_json::from_str(&text)?;
        if json.game_id == 0 {
            return Err(anyhow!("Hash not found"));
        }
        
        Ok(json.game_id)
    }

    pub fn get_game_data(&self, game_id: u64) -> Result<GameInfoAndUserProgress> {
        // API_GetGameInfoAndUserProgress.php?u={user}&y={key}&g={game_id}
        let url = format!(
            "{}/API_GetGameInfoAndUserProgress.php?u={}&y={}&g={}",
            BASE_URL, self.username, self.api_key, game_id
        );

        let response = self.client.get(&url)
            .header(USER_AGENT, "Theophany")
            .send()?;

        if !response.status().is_success() {
             return Err(anyhow!("Failed to get game info: {}", response.status()));
        }

        // RA sometimes returns an empty array [] if no data, instead of object. 
        // Deserializing might fail if that happens. But usually returns object for valid ID.
        let info: GameInfoAndUserProgress = response.json()?;
        
        Ok(info)
    }

    pub fn get_game_list(&self, console_id: u64) -> Result<Vec<GameListEntry>> {
        let url = format!(
            "{}/API_GetGameList.php?u={}&y={}&i={}",
            BASE_URL, self.username, self.api_key, console_id
        );

        let response = self.client.get(&url)
            .header(USER_AGENT, "Theophany")
            .send()?;

        if !response.status().is_success() {
             return Err(anyhow!("Failed to get game list: {}", response.status()));
        }

        let list: Vec<GameListEntry> = response.json()?;
        Ok(list)
    }

    pub fn get_console_ids(&self) -> Result<Vec<ConsoleIdEntry>> {
        let url = format!(
            "{}/API_GetConsoleIDs.php?u={}&y={}",
            BASE_URL, self.username, self.api_key
        );

        let response = self.client.get(&url)
            .header(USER_AGENT, "Theophany")
            .send()?;

        if !response.status().is_success() {
             return Err(anyhow!("Failed to get console ids: {}", response.status()));
        }

        let list: Vec<ConsoleIdEntry> = response.json()?;
        Ok(list)
    }

    pub fn download_image(&self, url_path: &str, destination: &std::path::Path) -> Result<()> {
        let url = format!("https://media.retroachievements.org{}", url_path);
        let mut response = self.client.get(&url).header(USER_AGENT, "Theophany").send()?;
        
        if !response.status().is_success() {
             return Err(anyhow!("Failed to download image: {}", response.status()));
        }
        
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        let mut file = std::fs::File::create(destination)?;
        response.copy_to(&mut file)?;
        Ok(())
    }

    pub fn get_user_summary(&self, target_user: &str, recent_games_count: u32) -> Result<UserSummary> {
        let url = format!(
            "{}/API_GetUserSummary.php?u={}&y={}&u={}&g={}&a=5",
            BASE_URL, self.username, self.api_key, target_user, recent_games_count
        );

        let response = self.client.get(&url)
            .header(USER_AGENT, "Theophany")
            .send()?;

        if !response.status().is_success() {
             return Err(anyhow!("Failed to get user summary: {}", response.status()));
        }

        let summary: UserSummary = response.json()?;
        Ok(summary)
    }
}
