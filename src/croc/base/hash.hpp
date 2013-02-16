#ifndef CROC_BASE_HASH_HPP
#define CROC_BASE_HASH_HPP

#include "croc/base/darray.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"

// #define HASH_FOREACH(K, Kname, V, Vname, h) { K* Kname; V* Vname; size_t idx; while(h.next(idx, Kname, Vname))
// #define HASH_FOREACH_END }

enum NodeFlags
{
	NodeFlags_Used =        (1 << 0),
	NodeFlags_KeyModified = (1 << 1),
	NodeFlags_ValModified = (1 << 2)
};

#define IS_USED(n) TEST_FLAG((n), NodeFlags_Used)
#define SET_USED(n) SET_FLAG((n), NodeFlags_Used)
#define CLEAR_USED(n) CLEAR_FLAG((n), NodeFlags_Used)

#define IS_KEY_MODIFIED(n) TEST_FLAG((n), NodeFlags_KeyModified)
#define SET_KEY_MODIFIED(n) SET_FLAG((n), NodeFlags_KeyModified)
#define CLEAR_KEY_MODIFIED(n) CLEAR_FLAG((n), NodeFlags_KeyModified)

#define IS_VAL_MODIFIED(n) TEST_FLAG((n), NodeFlags_ValModified)
#define SET_VAL_MODIFIED(n) SET_FLAG((n), NodeFlags_ValModified)
#define CLEAR_VAL_MODIFIED(n) CLEAR_FLAG((n), NodeFlags_ValModified)

namespace croc
{
	typedef uint32_t hash_t;

	struct DefaultHasher
	{
		template<typename T> static inline hash_t toHash(const T* t)
		{
			return cast(hash_t)*t;
		}
	};

	struct MethodHasher
	{
		template<typename T> static inline hash_t toHash(const T* t)
		{
			return t->toHash();
		}
	};

	template<typename K, typename V>
	struct HashNode
	{
		K key;
		V value;
		HashNode<K, V>* next;
		uint32_t flags;

		inline void init(hash_t hash)                 { (void)hash; }
		inline bool equals(const K& key, hash_t hash) { (void)hash; return this->key == key; }
		inline void copyFrom(HashNode<K, V>& other)   { value = other.value; }
	};

	template<typename K, typename V>
	struct HashNodeWithHash : HashNode<K, V>
	{
		hash_t hash;

		inline void init(hash_t hash)                 { this->hash = hash; }
		inline bool equals(const K& key, hash_t hash) { return this->hash == hash && this->key == key; }
		inline void copyFrom(HashNode<K, V>& other)   { this->value = other.value; hash = other.hash; }
	};

	template<typename K, typename V, typename Hasher = DefaultHasher, typename Node = HashNode<K, V> >
	struct Hash
	{
	private:
		DArray<Node> mNodes;
		uint32_t mHashMask;
		Node* mColBucket;
		size_t mSize;

	public:
		void prealloc(Memory& mem, size_t size)
		{
			if(size <= mNodes.length)
				return;
			else if(size > 4)
			{
				size_t newSize = 4;
				for(; newSize < size; newSize <<= 1) {}
				resizeArray(mem, newSize);
			}
		}

		V* insert(Memory& mem, K key)
		{
			return &insertNode(mem, key).value;
		}

		Node& insertNode(Memory& mem, K key)
		{
			hash_t hash = Hasher::toHash(&key);

			{
				Node* node = lookupNode(key, hash);

				if(node != NULL)
					return *node;
			}

			Node* colBucket = getColBucket();

			if(colBucket == NULL)
			{
				rehash(mem);
				colBucket = getColBucket();
				assert(colBucket != NULL);
			}

			Node* mainPosNode = &mNodes[hash & mHashMask];

			if(IS_USED(mainPosNode->flags))
			{
				Node* otherNode = &mNodes[Hasher::toHash(&mainPosNode->key) & mHashMask];

				if(otherNode == mainPosNode)
				{
					// other node is the head of its list, defer to it.
					colBucket->next = mainPosNode->next;
					mainPosNode->next = colBucket;
					mainPosNode = colBucket;
				}
				else
				{
					// other node is in the middle of a list, push it out.
					while(otherNode->next != mainPosNode)
						otherNode = otherNode->next;

					otherNode->next = colBucket;
					*colBucket = *mainPosNode;
					mainPosNode->next = NULL;
				}
			}
			else
				mainPosNode->next = NULL;

			mainPosNode->init(hash);
			mainPosNode->key = key;
			SET_USED(mainPosNode->flags);
			mSize++;

			return *mainPosNode;
		}

		bool remove(K key)
		{
			hash_t hash = Hasher::toHash(&key);
			Node* n = &mNodes[hash & mHashMask];

			if(!IS_USED(n->flags))
				return false;

			if(n->equals(key, hash))
			{
				// Removing head of list.
				if(n->next == NULL)
					// Only item in the list.
					markUnused(n);
				else
				{
					// Other items.  Have to move the next item into where the head used to be.
					Node* next = n->next;
					*n = *next;
					markUnused(next);
				}

				return true;
			}
			else
			{
				for(; n->next != NULL && IS_USED(n->next->flags); n = n->next)
				{
					if(n->next->equals(key, hash))
					{
						// Removing from the middle or end of the list.
						markUnused(n->next);
						n->next = n->next->next;
						return true;
					}
				}

				// Nonexistent key.
				return false;
			}
		}

		V* lookup(K key)
		{
			Node* ret = lookupNode(key, Hasher::toHash(&key));

			if(ret)
				return &ret->value;
			else
				return NULL;
		}

		V* lookup(K key, hash_t hash)
		{
			Node* ret = lookupNode(key, hash);

			if(ret)
				return &ret->value;
			else
				return NULL;
		}

		inline Node* lookupNode(K key)
		{
			return lookupNode(key, Hasher::hash(key));
		}

		Node* lookupNode(K key, hash_t hash)
		{
			if(mNodes.length == 0)
				return NULL;

			for(Node* n = &mNodes[hash & mHashMask]; n != NULL && IS_USED(n->flags); n = n->next)
				if(n->equals(key, hash))
					return n;

			return NULL;
		}

		bool next(size_t& idx, K*& key, V*& val)
		{
			for(; idx < mNodes.length; idx++)
			{
				if(IS_USED(mNodes[idx].flags))
				{
					key = &mNodes[idx].key;
					val = &mNodes[idx].value;
					idx++;
					return true;
				}
			}

			return false;
		}

		bool nextNode(size_t& idx, Node*& n)
		{
			for(; idx < mNodes.length; idx++)
			{
				if(IS_USED(mNodes[idx].flags))
				{
					n = &mNodes[idx++];
					return true;
				}
			}

			return false;
		}

		bool nextModified(size_t& idx, Node*& n)
		{
			for(; idx < mNodes.length; idx++)
			{
				if(IS_MODIFIED(mNodes[idx].flags))
				{
					n = &mNodes[idx++];
					return true;
				}
			}

			return false;
		}

		size_t length()
		{
			return mSize;
		}

		void minimize(Memory& mem)
		{
			if(mSize == 0)
				clear(mem);
			else
			{
				size_t newSize = 4;
				for(; newSize < mSize; newSize <<= 1) {}
				resizeArray(mem, newSize);
			}
		}

		void clear(Memory& mem)
		{
			mNodes.free(mem);
			mHashMask = 0;
			mColBucket = NULL;
			mSize = 0;
		}

	private:
		void markUnused(Node* n)
		{
			assert(n >= mNodes.ptr && n < mNodes.ptr + mNodes.length);

			CLEAR_USED(n->flags);

			if(n < mColBucket)
				mColBucket = n;

			mSize--;
		}

		void rehash(Memory& mem)
		{
			if(mNodes.length != 0)
				resizeArray(mem, mNodes.length * 2);
			else
				resizeArray(mem, 4);
		}

		void resizeArray(Memory& mem, size_t newSize)
		{
			DArray<Node> oldNodes = mNodes;

			mNodes = DArray<Node>::alloc(mem, newSize);
			mHashMask = mNodes.length - 1;
			mColBucket = mNodes.ptr;
			mSize = 0;

			for(size_t i = 0; i < oldNodes.length; i++)
			{
				Node& node = oldNodes[i];

				if(IS_USED(node.flags))
				{
					Node& newNode = insertNode(mem, node.key);
					newNode.copyFrom(node);
				}
			}

			oldNodes.free(mem);
		}

		Node* getColBucket()
		{
			for(Node* end = mNodes.ptr + mNodes.length; mColBucket < end; mColBucket++)
				if(!IS_USED(mColBucket->flags))
					return mColBucket;

			return NULL;
		}
	};
}

#endif
