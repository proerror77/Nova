import Foundation

/// GraphQL Queries and Mutations for Nova Social
enum GraphQL {
    // MARK: - Authentication

    static let login = """
    mutation Login($email: String!, $password: String!) {
      login(email: $email, password: $password) {
        accessToken
        refreshToken
        user {
          id
          username
          displayName
          avatarUrl
          isVerified
        }
      }
    }
    """

    static let register = """
    mutation Register($email: String!, $username: String!, $password: String!) {
      register(email: $email, username: $username, password: $password) {
        accessToken
        refreshToken
        user {
          id
          username
          displayName
          avatarUrl
          isVerified
        }
      }
    }
    """

    static let logout = """
    mutation Logout {
      logout
    }
    """

    // MARK: - Feed

    static let getFeed = """
    query GetFeed($limit: Int, $cursor: String) {
      feed(limit: $limit, cursor: $cursor) {
        posts {
          id
          userId
          caption
          imageUrl
          thumbnailUrl
          likeCount
          commentCount
          viewCount
          createdAt
          author {
            id
            username
            displayName
            avatarUrl
            isVerified
          }
          isLiked
        }
        cursor
        hasMore
      }
    }
    """

    // MARK: - Posts

    static let getPost = """
    query GetPost($id: ID!) {
      post(id: $id) {
        id
        userId
        caption
        imageUrl
        thumbnailUrl
        likeCount
        commentCount
        viewCount
        createdAt
        author {
          id
          username
          displayName
          avatarUrl
          isVerified
        }
        isLiked
      }
    }
    """

    static let createPost = """
    mutation CreatePost($caption: String, $imageUrl: String!) {
      createPost(input: {caption: $caption, imageUrl: $imageUrl}) {
        id
        userId
        caption
        imageUrl
        thumbnailUrl
        likeCount
        commentCount
        createdAt
      }
    }
    """

    static let deletePost = """
    mutation DeletePost($postId: ID!) {
      deletePost(postId: $postId)
    }
    """

    static let likePost = """
    mutation LikePost($postId: ID!) {
      likePost(postId: $postId)
    }
    """

    static let unlikePost = """
    mutation UnlikePost($postId: ID!) {
      unlikePost(postId: $postId)
    }
    """

    // MARK: - Users

    static let getMe = """
    query GetMe {
      me {
        id
        username
        displayName
        bio
        avatarUrl
        isVerified
        followerCount
        followingCount
        createdAt
      }
    }
    """

    static let getUser = """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        username
        displayName
        bio
        avatarUrl
        isVerified
        followerCount
        followingCount
        createdAt
      }
    }
    """

    static let updateProfile = """
    mutation UpdateProfile($displayName: String, $bio: String, $avatarUrl: String) {
      updateProfile(input: {displayName: $displayName, bio: $bio, avatarUrl: $avatarUrl}) {
        id
        username
        displayName
        bio
        avatarUrl
      }
    }
    """

    static let followUser = """
    mutation FollowUser($userId: ID!) {
      followUser(userId: $userId)
    }
    """

    static let unfollowUser = """
    mutation UnfollowUser($userId: ID!) {
      unfollowUser(userId: $userId)
    }
    """

    // MARK: - Search

    static let searchUsers = """
    query SearchUsers($query: String!, $limit: Int) {
      searchUsers(query: $query, limit: $limit) {
        id
        username
        displayName
        avatarUrl
        isVerified
        followerCount
      }
    }
    """

    static let searchPosts = """
    query SearchPosts($query: String!, $limit: Int) {
      search(query: $query, type: POST) {
        ... on Post {
          id
          userId
          caption
          imageUrl
          thumbnailUrl
          likeCount
          commentCount
          createdAt
          author {
            id
            username
            displayName
            avatarUrl
          }
        }
      }
    }
    """

    // MARK: - Notifications

    static let getNotifications = """
    query GetNotifications($limit: Int) {
      notifications(limit: $limit) {
        id
        userId
        notificationType
        title
        body
        isRead
        createdAt
      }
    }
    """

    static let getUnreadCount = """
    query GetUnreadCount {
      unreadCount
    }
    """

    static let markNotificationAsRead = """
    mutation MarkNotificationAsRead($notificationId: ID!) {
      markNotificationAsRead(notificationId: $notificationId)
    }
    """
}
