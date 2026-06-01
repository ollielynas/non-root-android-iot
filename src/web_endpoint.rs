

pub enum WebEndpoint {
    PocketBase{api_key: String, address:String}
}

impl WebEndpoint {
    pub fn name(&self) -> String {
        match self {
            Self::PocketBase { api_key: _, address: _ } => "PocketBase.io",
        }.to_string()
    }
}
